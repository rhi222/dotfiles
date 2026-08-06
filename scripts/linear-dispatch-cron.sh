#!/bin/bash
# LinearのAI Ready issueを夜間にheadless Claudeで実行し、draft PRまで進める
#
# crontab設定例:
#   0 1 * * 2-6 $HOME/scripts/linear-dispatch-cron.sh >> $HOME/.linear-dispatch.log 2>&1
#
# 有効化: touch ~/.config/linear-dispatch-enabled
# 無効化: rm ~/.config/linear-dispatch-enabled
#
# issue本文の契約:
#   repo: github.com/<owner>/<name>   ← 必須。無ければTodoへ差し戻す
#   （残りの本文全体がそのままプロンプトの素材になる）
#
# 安全弁:
#   - 「判断待ち」が LINEAR_WIP_LIMIT（既定10）件以上なら実行しない
#   - 1晩の実行上限 LINEAR_DISPATCH_MAX（既定3）
#   - 成果物はdraft PRまで。マージはしない
#
# 【重要】外部システムへ書き戻さない。既存のGitHub issue / Jiraチケットへの
# コメント・ラベル付与・ステータス変更は禁止。新規に作るdraft PRの本文にも
# Linearのissue識別子を書かない。対応関係はLinear issue側のコメントに残す。
set -euo pipefail

# $0 ではなく BASH_SOURCE を使う。テストが関数単体を source して呼ぶため
# （bash -c 経由だと $0 が "bash" になり lib の解決に失敗する）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/linear-api.sh"

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
LINEAR_WIP_LIMIT="${LINEAR_WIP_LIMIT:-10}"
LINEAR_DISPATCH_MAX="${LINEAR_DISPATCH_MAX:-3}"
ALLOWED_TOOLS="Read,Write,Edit,Glob,Grep,Bash(git:*),Bash(gh:*),Bash(jq:*),Bash(npm:*),Bash(npx:*),Bash(node:*),Bash(python3:*),Bash(pytest:*),Bash(make:*),Bash(cargo:*),Bash(go:*),Bash(ls:*),Bash(cat:*),Bash(mkdir:*)"

# dispatch_parse_repo <description> → repo（例 github.com/example-org/repo1）。無ければ非0
#
# Linearは本文中の `github.com/owner/name` を自動でmarkdownリンクに変換するため
# `repo: [github.com/o/n](<http://github.com/o/n>)` の形で保存されることがある。
# host/owner/name の3要素だけを抜き出してどちらの形式でも同じ結果にする。
dispatch_parse_repo() {
  local line repo
  line=$(grep -m1 -E '^repo:' <<<"$1") || return 1
  repo=$(grep -oE '[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' <<<"$line" | head -1)
  [[ -n "$repo" ]] || return 1
  echo "$repo"
}

# dispatch_parse_pr_url <claude-log> → PR URL。無ければ非0
dispatch_parse_pr_url() {
  local url
  url=$(grep -oE 'PR_URL:[[:space:]]*https://[^[:space:]]+' <<<"$1" | tail -1 | sed 's/^PR_URL:[[:space:]]*//')
  [[ -n "$url" ]] || return 1
  echo "$url"
}

# dispatch_bounce <issueId> <message>
# 実行せずTodoへ差し戻す。理由をコメントに残す（黙って消えないようにする）
dispatch_bounce() {
  linear_comment "$1" "$2"
  linear_issue_move "$1" "Todo"
}

# dispatch_one <issue-json>
dispatch_one() {
  local issue="$1"
  local id identifier title desc repo repo_path wt branch log pr_url status
  id=$(jq -r '.id' <<<"$issue")
  identifier=$(jq -r '.identifier' <<<"$issue")
  title=$(jq -r '.title' <<<"$issue")
  desc=$(jq -r '.description // ""' <<<"$issue")

  if ! repo=$(dispatch_parse_repo "$desc"); then
    dispatch_bounce "$id" "dispatch失敗: 本文に \`repo: github.com/<owner>/<name>\` 行が無い。追記して AI Ready に戻してほしい"
    echo "$identifier: BOUNCED (no repo)"
    return 0
  fi
  repo_path="$(ghq root)/$repo"
  if [[ ! -d "$repo_path" ]]; then
    dispatch_bounce "$id" "dispatch失敗: ローカルにrepoが無い: \`$repo_path\`（ghq get してほしい）"
    echo "$identifier: BOUNCED (no local repo)"
    return 0
  fi

  branch="linear/$identifier"
  wt="$repo_path/.wt/linear-$identifier"
  if ! git -C "$repo_path" worktree add "$wt" -b "$branch" >/dev/null 2>&1; then
    dispatch_bounce "$id" "dispatch失敗: worktree作成に失敗（\`$branch\` が既存の可能性。前回分を整理してほしい）"
    echo "$identifier: BOUNCED (worktree)"
    return 0
  fi

  linear_issue_move "$id" "AI Running"

  local prompt="以下のタスクを完遂してほしい。

# タスク: $title

$desc

# 進め方の契約
- TDDで進める（テスト先行）。既存のテスト・lintを壊さない
- こまめにconventional commitsでコミットする（Claude署名は付けない）
- 完了したらブランチをpushし、\`gh pr create --draft\` でdraft PRを作る
- PR本文にLinearのissue識別子（NSY-xx）を書かない。既存のGitHub issue / Jira
  チケットへのコメント・ラベル付与・ステータス変更も一切しない
- 最後に、標準出力の最終行として「PR_URL: <作成したPRのURL>」を必ず出力する
- 途中で完遂不能と判断したら、理由を出力して終了する（PR_URL行は出さない）"

  set +e
  log=$(cd "$wt" && "$CLAUDE_BIN" -p "$prompt" --allowedTools "$ALLOWED_TOOLS" 2>&1)
  status=$?
  set -e

  if [[ $status -eq 0 ]] && pr_url=$(dispatch_parse_pr_url "$log"); then
    linear_comment "$id" "夜間dispatch完了: $pr_url"
    linear_issue_move "$id" "判断待ち"
    echo "$identifier: OK $pr_url"
  else
    linear_comment "$id" "夜間dispatch失敗。ログ末尾:

\`\`\`
$(tail -20 <<<"$log")
\`\`\`"
    linear_issue_move "$id" "Todo"
    echo "$identifier: FAILED"
  fi
}

main() {
  [[ -f "$HOME/.config/linear-dispatch-enabled" ]] || exit 0

  local wip ready count issue
  wip=$(linear_issues_in_state "判断待ち" | jq 'length')
  if [[ "$wip" -ge "$LINEAR_WIP_LIMIT" ]]; then
    echo "$(date): WIP上限（判断待ち ${wip}件 >= ${LINEAR_WIP_LIMIT}）。dispatchをスキップ。朝の判断タイムで捌いてほしい"
    exit 0
  fi

  ready=$(linear_issues_in_state "AI Ready")
  count=$(jq 'length' <<<"$ready")
  if [[ "$count" -eq 0 ]]; then
    echo "$(date): AI Readyが0件。何もしない"
    exit 0
  fi

  # パイプにするとサブシェルになるためプロセス置換を使う
  while read -r issue; do
    dispatch_one "$issue"
  done < <(jq -c ".[:$LINEAR_DISPATCH_MAX][]" <<<"$ready")
  echo "$(date): linear-dispatch done"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
