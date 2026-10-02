#!/bin/bash
# 自分のopen PRを夜間に見張り、CI失敗と未対応レビューをheadless Claudeで直す
#
# crontab設定例:
#   30 1 * * 2-6 $HOME/scripts/prwatch/nightly.sh >> $HOME/.pr-watch.log 2>&1
#
# 有効化: touch ~/.config/pr-watch-enabled   （--dry-run はフラグ無しでも判定だけ出す）
#
# 対象: `gh search prs --author @me --state open` のうち、次のどれかに当たるもの
#   - ci:       最新コミットのCIが FAILURE / ERROR
#   - feedback: 未解決かつoutdatedでないレビュースレッドがある、または CHANGES_REQUESTED
#
# 安全弁:
#   - pushするのはdraft PRだけ。レビュー中のPRは修正をworktreeに残し「push待ち」と報告する
#   - ローカルブランチは触らない。worktreeはdetachedで作り、`HEAD:<branch>` へpushする
#     （同名のローカルブランチに未pushの作業があっても壊さない）
#   - 対応したheadのSHAを記録し、同じheadでは翌晩以降に繰り返さない
#   - agentには gh を渡さない。CIログとレビュー指摘はスクリプトが取得して渡す
#   - GitHubへはコメント・resolve・ラベルなど一切書き込まない。pushだけ
set -euo pipefail

# cronのPATH（/usr/bin:/bin）には mise 管理の gh / ghq が無い。末尾に足すのは、
# 既にPATHにあるもの（対話シェル・テストのstub）を優先させるため
export PATH="$PATH:$HOME/.local/share/mise/shims"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$REPO_ROOT/internal/automation/cron-claude.sh"

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
CLAUDE_TIMEOUT="${PR_WATCH_TIMEOUT:-1800}"
PR_WATCH_MAX="${PR_WATCH_MAX:-3}"
STATE_DIR="${PR_WATCH_STATE_DIR:-$HOME/.local/state/pr-watch}"
ALLOWED_TOOLS="Read,Write,Edit,Glob,Grep,Bash(git:*),Bash(jq:*),Bash(npm:*),Bash(npx:*),Bash(node:*),Bash(python3:*),Bash(pytest:*),Bash(make:*),Bash(cargo:*),Bash(go:*),Bash(ls:*),Bash(cat:*),Bash(mkdir:*)"

PR_QUERY='query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { pullRequest(number: $number) {
    headRefName headRefOid isDraft reviewDecision
    commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    reviewThreads(first: 100) { nodes { isResolved isOutdated path line
      comments(first: 10) { nodes { body author { login } } } } }
  } } }'

# prwatch_reasons <pr-json> → 対応が要る理由を1行ずつ（ci / feedback）。無ければ何も出さない
prwatch_reasons() {
  jq -r '
    (if (.commits.nodes[0].commit.statusCheckRollup.state // "") | IN("FAILURE","ERROR") then "ci" else empty end),
    (if ([.reviewThreads.nodes[] | select(.isResolved | not) | select(.isOutdated | not)] | length) > 0
        or .reviewDecision == "CHANGES_REQUESTED" then "feedback" else empty end)' <<<"$1"
}

# prwatch_feedback_text <pr-json> → 未解決スレッドの場所と本文
prwatch_feedback_text() {
  jq -r '.reviewThreads.nodes[] | select(.isResolved | not) | select(.isOutdated | not)
    | "### \(.path):\(.line // "-")\n" + ([.comments.nodes[] | "- \(.author.login // "?"): \(.body)"] | join("\n"))' <<<"$1"
}

# prwatch_ci_log <owner/name> <branch> → 直近の失敗runのログ末尾
prwatch_ci_log() {
  local run
  run=$(gh run list --repo "$1" --branch "$2" --status failure --limit 1 --json databaseId 2>/dev/null |
    jq -r '.[0].databaseId // empty') || return 0
  [[ -n "$run" ]] || return 0
  gh run view "$run" --repo "$1" --log-failed 2>/dev/null | tail -200 || true
}

# prwatch_one <url> <dry-run 0/1> → 結果を1行でstdoutへ
prwatch_one() {
  local url="$1" dry="$2"
  local slug owner name number pr reasons key head branch repo_path wt before after prompt log out_file
  slug="${url#https://github.com/}" # owner/name/pull/N
  owner="${slug%%/*}"
  name="${slug#*/}" && name="${name%%/*}"
  number="${slug##*/}"

  pr=$(gh api graphql -f query="$PR_QUERY" -F owner="$owner" -F name="$name" -F number="$number" 2>/dev/null |
    jq -ec '.data.repository.pullRequest') || {
    echo "$url: SKIP (PR情報を取得できなかった)"
    return 0
  }
  reasons=$(prwatch_reasons "$pr" | paste -sd, -)
  [[ -n "$reasons" ]] || return 0

  key="$STATE_DIR/${owner}_${name}_${number}.sha"
  head=$(jq -r '.headRefOid' <<<"$pr")
  if [[ -f "$key" && "$(cat "$key")" == "$head" ]]; then
    echo "$url: SKIP [$reasons] (このheadは対応済み。人の確認待ち)"
    return 0
  fi
  branch=$(jq -r '.headRefName' <<<"$pr")
  repo_path="$(ghq root)/github.com/$owner/$name"
  wt="$repo_path/.wt/pr-watch-$number"
  if [[ -d "$wt" ]]; then
    echo "$url: SKIP [$reasons] push待ちの修正あり: cd $wt && git push origin HEAD:$branch"
    return 0
  fi
  if [[ "$dry" == "1" ]]; then
    echo "$url: WOULD FIX [$reasons] $(jq -r 'if .isDraft then "draft" else "review中" end' <<<"$pr")"
    return 0
  fi
  if [[ ! -d "$repo_path" ]]; then
    echo "$url: SKIP [$reasons] (ローカルにrepoが無い: $repo_path)"
    return 0
  fi

  git -C "$repo_path" fetch -q origin "$branch" 2>/dev/null || {
    echo "$url: SKIP [$reasons] (fetchに失敗)"
    return 0
  }
  git -C "$repo_path" worktree add -q --detach "$wt" "origin/$branch" 2>/dev/null || {
    echo "$url: SKIP [$reasons] (worktree作成に失敗)"
    return 0
  }
  before=$(git -C "$wt" rev-parse HEAD)

  # 理由に当たる欄だけを渡す。空のCIログ欄を渡すと、agentが落ちていないCIを調べに行く
  prompt="PR $url の問題を直してほしい。対応が要る理由: $reasons"
  if [[ "$reasons" == *feedback* ]]; then
    prompt+="

# 未対応のレビュー指摘（botの指摘も含む）
$(prwatch_feedback_text "$pr")"
  fi
  if [[ "$reasons" == *ci* ]]; then
    prompt+="

# CIの失敗ログ（末尾）
\`\`\`
$(prwatch_ci_log "$owner/$name" "$branch")
\`\`\`"
  fi
  prompt+="

# 進め方の契約
- 指摘とCI失敗の原因を直し、テストとlintが通る状態でconventional commitsでコミットする（Claude署名は付けない）
- 指摘が妥当でない・判断が要るものはコードを変えずに理由を出力する
- **pushしない。** GitHubへのコメント・resolveもしない。pushは呼び出し元が判断する
- 直せないと判断したら、理由を出力してコミットせずに終了する"

  set +e
  log=$(cd "$wt" && cron_run_claude "PR見張り $url" "$CLAUDE_TIMEOUT" "$CLAUDE_BIN" \
    -p "$prompt" --allowedTools "$ALLOWED_TOOLS" 2>&1)
  set -e
  after=$(git -C "$wt" rev-parse HEAD)
  # 指摘ごとの判断理由を朝に読めるよう、全文をPRごとに残す（前回分は上書き）
  out_file="${key%.sha}.log"
  printf '%s\n' "$log" >"$out_file"

  if [[ "$after" == "$before" ]]; then
    # 直せなかったheadを毎晩繰り返さない。新しいpushかレビューで head が変われば再挑戦する
    echo "$head" >"$key"
    git -C "$repo_path" worktree remove --force "$wt" >/dev/null 2>&1 || true
    echo "$url: NO CHANGE [$reasons] コードは変えなかった。判断の全文: $out_file"
    return 0
  fi
  if [[ "$(jq -r '.isDraft' <<<"$pr")" != "true" ]]; then
    echo "$url: FIXED [$reasons] push待ち（レビュー中のため自動pushしない）: cd $wt && git push origin HEAD:$branch 判断の全文: $out_file"
    return 0
  fi
  if ! git -C "$wt" push -q origin "HEAD:refs/heads/$branch" 2>/dev/null; then
    echo "$url: FIXED [$reasons] pushに失敗（remoteが進んだ可能性）。worktreeを残す: $wt 判断の全文: $out_file"
    return 0
  fi
  echo "$after" >"$key"
  git -C "$repo_path" worktree remove --force "$wt" >/dev/null 2>&1 || true
  echo "$url: PUSHED [$reasons] draftへ修正をpushした。判断の全文: $out_file"
}

main() {
  local dry=0
  [[ "${1:-}" == "--dry-run" ]] && dry=1
  [[ "$dry" == "1" ]] || cron_require_flag "$HOME/.config/pr-watch-enabled"
  mkdir -p "$STATE_DIR"

  local urls url line result="" fixed=0
  urls=$(gh search prs --author @me --state open --limit 50 --json url | jq -r '.[].url')
  while read -r url; do
    [[ -n "$url" ]] || continue
    line=$(prwatch_one "$url" "$dry") || line="$url: ERROR (想定外の失敗。次へ進む)"
    [[ -n "$line" ]] || continue
    echo "$line"
    result+="$line"$'\n'
    [[ "$line" == *": FIXED "* || "$line" == *": PUSHED "* || "$line" == *": NO CHANGE "* ]] && fixed=$((fixed + 1))
    [[ "$fixed" -lt "$PR_WATCH_MAX" ]] || break
  done <<<"$urls"

  [[ "$dry" == "1" ]] || printf '%s: pr-watch\n%s' "$(date '+%F %T')" "$result" >"$STATE_DIR/last-run.txt"
  echo "$(date): pr-watch done"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
