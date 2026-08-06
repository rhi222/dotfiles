#!/bin/bash
# gh（自分のdraft PR）とJira（担当チケット）をLinear Triageへ自動起票する
#
# 他者PRのレビュー依頼は対象外。GitHubのレビュー受信箱と二重管理になるため。
#
# crontab設定例:
#   0 8 * * 1-5 $HOME/scripts/linear-sweep.sh >> $HOME/.linear-sweep.log 2>&1
#
# 有効化: touch ~/.config/linear-sweep-enabled
# 無効化: rm ~/.config/linear-sweep-enabled
#
# Jiraを有効にする場合: ~/.config/linear/jira.env に
#   JIRA_BASE_URL=https://<org>.atlassian.net
#   JIRA_EMAIL=<email>
#   JIRA_API_TOKEN=<token>
# を置く。無ければJiraスイープはスキップされる。
#
# 【重要】外部システム（GitHub/Jira）へは一切書き戻さない。
# 読み取りAPIのみを使う（ghは search、Jiraは GET）。外部issue・チケットへの
# コメント／ラベル付与／ステータス変更／issue作成をしない。リンクは
# Linear → 外部 の一方向のみ。test-linear-sweep.sh がこれを検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/linear-api.sh"

SEEN="${LINEAR_SWEEP_SEEN:-$HOME/.local/state/linear-sweep/seen.txt}"
# 1回のスイープで起票する上限。初回の様子見や、想定外の大量起票を防ぐ保険
LINEAR_SWEEP_MAX="${LINEAR_SWEEP_MAX:-50}"
swept_count=0

# 作成者がこのglobに一致するPRはスイープしない。
# dependabot / auto-merge-github-app のようなbot PRは自動マージ対象で、
# Triage（＝人間が選別する受信箱）に積んでも判断の余地が無いため。
LINEAR_SWEEP_EXCLUDE_AUTHORS="${LINEAR_SWEEP_EXCLUDE_AUTHORS:-*\[bot\]}"

# sweep_author_excluded <author>
sweep_author_excluded() {
  local a="$1" pat
  for pat in $LINEAR_SWEEP_EXCLUDE_AUTHORS; do
    # shellcheck disable=SC2254
    case "$a" in $pat) return 0 ;; esac
  done
  return 1
}

# sweep_item <url> <title> <label名>
# seen済みならスキップ、未登録ならTriageに起票してseenへ追記する
sweep_item() {
  local url="$1" title="$2" label="$3"
  [[ -f "$SEEN" ]] && grep -qxF "$url" "$SEEN" && return 0
  if [[ "$swept_count" -ge "$LINEAR_SWEEP_MAX" ]]; then
    return 0
  fi
  linear_issue_create "$title" "元URL: $url" "Triage" "$label" >/dev/null
  mkdir -p "$(dirname "$SEEN")"
  echo "$url" >> "$SEEN"
  swept_count=$((swept_count + 1))
  echo "swept: $url"
}

sweep_github() {
  local json pr author
  # 自分のopen draft PR（読み取りのみ）
  #
  # 他者PRのレビュー依頼はスイープしない。GitHubのレビュー受信箱と二重管理になるうえ、
  # 常時20〜30件あるためTriageが溢れて「人間が選別する受信箱」として機能しなくなる。
  # レビューはGitHub側の導線で捌く。
  if json=$(gh search prs --author=@me --state=open --draft --json url,title,author --limit 100 2>/dev/null); then
    # パイプにするとサブシェルになり swept_count が親へ反映されないためプロセス置換を使う
    while read -r pr; do
      author=$(jq -r '.author.login // ""' <<<"$pr")
      if sweep_author_excluded "$author"; then
        echo "skip(bot): $(jq -r '.url' <<<"$pr")"
        continue
      fi
      sweep_item "$(jq -r '.url' <<<"$pr")" "draft仕上げ: $(jq -r '.title' <<<"$pr")" "src:github"
    done < <(jq -c '.[]' <<<"$json")
  else
    echo "linear-sweep: gh検索に失敗（draft）。スキップする" >&2
  fi
}

sweep_jira() {
  local env_file="$LINEAR_CONFIG_DIR/jira.env"
  if [[ ! -f "$env_file" ]]; then
    echo "linear-sweep: jira.env無し。Jiraスイープをスキップ"
    return 0
  fi
  # shellcheck disable=SC1090
  source "$env_file"
  local resp
  # GETのみ。Jira側へは何も書き込まない
  if ! resp=$(curl -sS -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    --get "$JIRA_BASE_URL/rest/api/3/search/jql" \
    --data-urlencode 'jql=assignee = currentUser() AND statusCategory != Done' \
    --data-urlencode 'fields=summary' 2>/dev/null); then
    echo "linear-sweep: Jira APIに失敗。スキップする" >&2
    return 0
  fi
  local issue key
  while read -r issue; do
    key=$(jq -r '.key' <<<"$issue")
    sweep_item "$JIRA_BASE_URL/browse/$key" "[$key] $(jq -r '.fields.summary' <<<"$issue")" "src:jira"
  done < <(jq -c '.issues[]?' <<<"$resp")
}

main() {
  [[ -f "$HOME/.config/linear-sweep-enabled" ]] || exit 0
  sweep_github
  sweep_jira
  echo "$(date): linear-sweep done"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
