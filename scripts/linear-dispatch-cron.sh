#!/bin/bash
# LinearのAI Queued issueを夜間にheadless Claudeで実行し、draft PRまで進める
#
# crontab設定例:
#   0 1 * * 2-6 $HOME/scripts/linear-dispatch-cron.sh >> $HOME/.linear-dispatch.log 2>&1
#
# 有効化: touch ~/.config/linear-dispatch-enabled
# 無効化: rm ~/.config/linear-dispatch-enabled
#
# issue本文の契約（2モード）:
#   継続モード: 本文に既存PRのURL（github.com/o/n/pull/N）があれば、そのPRのブランチを
#               checkoutして続きを進める。新規PRは作らない
#   新規モード: PR URLが無ければ `repo: github.com/<owner>/<name>` 行を読み、
#               linear/<identifier> ブランチを切って新規PRを作る
#   どちらも無ければTodoへ差し戻す。残りの本文全体がそのままプロンプトの素材になる
#
# 起動条件は state = "AI Queued" の1点。ラベルは見ない（stateと二重に持たない）
#
# 安全弁:
#   - 「My Review」が LINEAR_WIP_LIMIT（既定10）件以上なら実行しない
#     （他人待ちの「Waiting」は自分の判断負荷ではないので数えない）
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
# agentには gh を渡さない。push・PR作成はスクリプトの責務なので、
# ネットワーク書き込み権限をagentに与える必要がない
ALLOWED_TOOLS="Read,Write,Edit,Glob,Grep,Bash(git:*),Bash(jq:*),Bash(npm:*),Bash(npx:*),Bash(node:*),Bash(python3:*),Bash(pytest:*),Bash(make:*),Bash(cargo:*),Bash(go:*),Bash(ls:*),Bash(cat:*),Bash(mkdir:*)"

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

# dispatch_parse_pr_url <description> → owner/name/number（例 example-org/repo1/42）。無ければ非0
# LinearはURLをmarkdownリンク化するので、リンク記法でも素のURLでも拾えるようにする
dispatch_parse_pr_url() {
  local m
  m=$(grep -oE 'github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+' <<<"$1" | head -1)
  [[ -n "$m" ]] || return 1
  sed -E 's#^github\.com/##' <<<"$m" | sed -E 's#/pull/#/#'
}

# dispatch_can_create_pr <owner/name>
# PR作成に足る権限があれば0。無い/判定不能なら非0（安全側に倒す）
dispatch_can_create_pr() {
  local perm
  perm=$(gh repo view "$1" --json viewerPermission -q '.viewerPermission' 2>/dev/null) || return 1
  case "$perm" in
    ADMIN | MAINTAIN | WRITE) return 0 ;;
    *) return 1 ;;
  esac
}

# dispatch_one <issue-json>
dispatch_one() {
  local issue="$1"
  local id identifier title desc repo repo_path wt branch log status
  local mode existing_pr pr_ref pr_json pr_state pr_url
  id=$(jq -r '.id' <<<"$issue")
  identifier=$(jq -r '.identifier' <<<"$issue")
  title=$(jq -r '.title' <<<"$issue")
  desc=$(jq -r '.description // ""' <<<"$issue")

  # モード判定: 本文に既存PRのURLがあれば「継続」、無ければ「新規」。
  # draft仕上げ系の子issueは既存のdraft PRを指しているので、新規ブランチを切ると
  # 元のPRと無関係な重複PRができてしまう
  if pr_ref=$(dispatch_parse_pr_url "$desc"); then
    mode="continue"
    repo="github.com/${pr_ref%/*}" # example-org/repo1/42 → github.com/example-org/repo1
    existing_pr="${pr_ref##*/}"    # → 42
  else
    mode="new"
    if ! repo=$(dispatch_parse_repo "$desc"); then
      dispatch_bounce "$id" "dispatch失敗: 本文に \`repo: github.com/<owner>/<name>\` 行も既存PRのURLも無い。どちらかを書いて AI Queued に戻してほしい"
      echo "$identifier: BOUNCED (no repo)"
      return 0
    fi
  fi
  repo_path="$(ghq root)/$repo"
  if [[ ! -d "$repo_path" ]]; then
    dispatch_bounce "$id" "dispatch失敗: ローカルにrepoが無い: \`$repo_path\`（ghq get してほしい）"
    echo "$identifier: BOUNCED (no local repo)"
    return 0
  fi

  # PR作成権限を先に確認する。無いまま走らせると、agentを1回丸ごと動かした末に
  # 最後の gh pr create だけが失敗して数分とトークンを捨てることになる
  if ! dispatch_can_create_pr "${repo#github.com/}"; then
    dispatch_bounce "$id" "dispatch失敗: \`${repo#github.com/}\` にPRを作る権限が無い（またはgh認証が別アカウント）。ghのログイン先を確認してほしい"
    echo "$identifier: BOUNCED (no PR permission)"
    return 0
  fi

  wt="$repo_path/.wt/linear-$identifier"
  if [[ "$mode" == "continue" ]]; then
    # 既存PRのブランチを取ってきて、その上で作業する
    pr_json=$(gh pr view "$existing_pr" --repo "${repo#github.com/}" \
      --json headRefName,state,url 2>/dev/null) || {
      dispatch_bounce "$id" "dispatch失敗: 既存PR #${existing_pr} の情報を取得できなかった"
      echo "$identifier: BOUNCED (pr view)"
      return 0
    }
    branch=$(jq -r '.headRefName' <<<"$pr_json")
    pr_state=$(jq -r '.state' <<<"$pr_json")
    pr_url=$(jq -r '.url' <<<"$pr_json")
    if [[ "$pr_state" != "OPEN" ]]; then
      dispatch_bounce "$id" "dispatch失敗: 既存PR #${existing_pr} は ${pr_state} で、続きを進められない"
      echo "$identifier: BOUNCED (pr not open)"
      return 0
    fi
    git -C "$repo_path" fetch origin "$branch" >/dev/null 2>&1 || true
    if ! git -C "$repo_path" worktree add "$wt" "$branch" >/dev/null 2>&1; then
      dispatch_bounce "$id" "dispatch失敗: worktree作成に失敗（\`$branch\` が既にどこかでcheckout済みの可能性）"
      echo "$identifier: BOUNCED (worktree)"
      return 0
    fi
  else
    branch="linear/$identifier"
    if ! git -C "$repo_path" worktree add "$wt" -b "$branch" >/dev/null 2>&1; then
      dispatch_bounce "$id" "dispatch失敗: worktree作成に失敗（\`$branch\` が既存の可能性。前回分を整理してほしい）"
      echo "$identifier: BOUNCED (worktree)"
      return 0
    fi
  fi

  # 作業前のHEADを控える。コミットが積まれたかの判定を両モードで共通にする
  local head_before
  head_before=$(git -C "$wt" rev-parse HEAD 2>/dev/null || echo "")

  linear_issue_move "$id" "AI Running"

  local prompt="以下のタスクを完遂してほしい。

# タスク: $title

$desc

# 進め方の契約
- TDDで進める（テスト先行）。既存のテスト・lintを壊さない
- こまめにconventional commitsでコミットする（Claude署名は付けない）
- **pushしない。PRも作らない。** この2つは呼び出し元のスクリプトが行う
- PR本文にLinearのissue識別子（NSY-xx）を書かない。既存のGitHub issue / Jira
  チケットへのコメント・ラベル付与・ステータス変更も一切しない
- 既存のGitHub issue / Jira チケットへのコメント・ラベル付与・ステータス変更も一切しない
- 完了条件はローカルコミットが積まれていること。テストが通る状態で終える
- 途中で完遂不能と判断したら、理由を出力してコミットせずに終了する"

  set +e
  log=$(cd "$wt" && "$CLAUDE_BIN" -p "$prompt" --allowedTools "$ALLOWED_TOOLS" 2>&1)
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    dispatch_finish_failed "$id" "$identifier" "$log" "claude実行が異常終了した（exit $status）"
    return 0
  fi

  # コミットが積まれたか確認する。作業前のHEADと比べるので両モードで同じ判定が使える
  local head_after
  head_after=$(git -C "$wt" rev-parse HEAD 2>/dev/null || echo "")
  if [[ -z "$head_after" || "$head_after" == "$head_before" ]]; then
    dispatch_finish_failed "$id" "$identifier" "$log" "コミットが1つも積まれていない（実装に到達しなかった）"
    return 0
  fi

  # push と PR作成はスクリプトが行う。
  # agentに任せるとClaude Codeの権限層に阻まれる（許可リストでは上書きできない）うえ、
  # そもそもagentにネットワーク書き込み権限を渡さずに済む
  if ! git -C "$wt" push -u origin "$branch" >/dev/null 2>&1; then
    dispatch_finish_failed "$id" "$identifier" "$log" "git push に失敗した（ブランチ $($branch)）"
    return 0
  fi

  # 継続モードは既存PRにコミットが乗るだけなので、新規PRは作らない
  if [[ "$mode" == "new" ]]; then
    if ! pr_url=$(gh pr create --draft --repo "${repo#github.com/}" --head "$branch" \
      --title "$title" --body "夜間dispatchによる自動実装。レビュー前のdraft。" 2>&1); then
      dispatch_finish_failed "$id" "$identifier" "$log" "gh pr create に失敗した: $pr_url"
      return 0
    fi
    linear_comment "$id" "夜間dispatch完了（新規PR）: $pr_url"
  else
    linear_comment "$id" "夜間dispatch完了（既存PRを更新）: $pr_url"
  fi
  linear_issue_move "$id" "My Review"
  echo "$identifier: OK $pr_url"
}

# dispatch_finish_failed <issueId> <identifier> <claudeログ> <理由>
# 理由とログ末尾をコメントしてTodoへ差し戻す（黙って消えないようにする）
dispatch_finish_failed() {
  local id="$1" identifier="$2" log="$3" reason="$4"
  linear_comment "$id" "夜間dispatch失敗: ${reason}

ログ末尾:

\`\`\`
$(tail -20 <<<"$log")
\`\`\`"
  linear_issue_move "$id" "Todo"
  echo "$identifier: FAILED ($reason)"
}

main() {
  [[ -f "$HOME/.config/linear-dispatch-enabled" ]] || exit 0

  local wip ready count issue
  wip=$(linear_issues_in_state "My Review" | jq 'length')
  if [[ "$wip" -ge "$LINEAR_WIP_LIMIT" ]]; then
    echo "$(date): WIP上限（My Review ${wip}件 >= ${LINEAR_WIP_LIMIT}）。dispatchをスキップ。朝の判断タイムで捌いてほしい"
    exit 0
  fi

  ready=$(linear_issues_in_state "AI Queued")
  count=$(jq 'length' <<<"$ready")
  if [[ "$count" -eq 0 ]]; then
    echo "$(date): AI Queuedが0件。何もしない"
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
