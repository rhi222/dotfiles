#!/bin/bash
# 返事待ち・頼まれ事のまとめ（cron用ラッパー）
# 平日の毎時に followup スキルをヘッドレス実行し、🆕があればWindows toastを出す。
#
# crontab設定例:
#   0 9-18 * * 1-5 $HOME/scripts/followup/digest-cron.sh >> $HOME/.followup-cron.log 2>&1
#
# 有効化: touch ~/.config/followup-enabled
# 無効化: rm ~/.config/followup-enabled
# 動作確認: FOLLOWUP_DRY_RUN=1 FOLLOWUP_FORCE=1 bash scripts/followup/digest-cron.sh
#
# 【重要】Slack・Jiraへは一切書き込まない。--allowedTools に読み取り系しか入れないことが
# その担保になっている。tests/followup/test-digest-cron.sh がこれを検証する。
set -euo pipefail

DOMAIN_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
REPO_ROOT="$(cd "$DOMAIN_DIR/../.." && pwd)"
source "$REPO_ROOT/internal/automation/cron-claude.sh"

cron_require_flag "$HOME/.config/followup-enabled"
cron_weekday_only "${FOLLOWUP_FORCE:-0}"

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
STATE_DIR="${FOLLOWUP_STATE_DIR:-$HOME/.local/state/followup}"
# 毎時走るので、次の起動と重ならない長さに抑える
CLAUDE_TIMEOUT="${FOLLOWUP_TIMEOUT:-600}"
PROMPT="/followup"
# skill の allowed-tools と一致させる。書き込み系は意図的に入れていない
ALLOWED_TOOLS="Bash(dotctl:*),mcp__claude_ai_Slack__slack_search_public_and_private,mcp__claude_ai_Slack__slack_read_thread,mcp__claude_ai_Slack__slack_read_user_profile,mcp__claude_ai_Atlassian__getAccessibleAtlassianResources,mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql"

if [[ "${FOLLOWUP_DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN: cd $REPO_ROOT && timeout $CLAUDE_TIMEOUT $CLAUDE_BIN -p \"$PROMPT\" --allowedTools \"$ALLOWED_TOOLS\""
  exit 0
fi

cd "$REPO_ROOT"
# cron の PATH には ~/.local/bin（dotctl・claude の置き場）が無いことがある
export PATH="$HOME/.local/bin:$PATH"
# dotctl が書く状態ディレクトリを cron 側と揃える
export FOLLOWUP_STATE_DIR="$STATE_DIR"
cron_run_claude "followup" "$CLAUDE_TIMEOUT" "$CLAUDE_BIN" \
  -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS"

notice="$STATE_DIR/notice"
if [[ -s "$notice" ]]; then
  if [[ -n "${FOLLOWUP_TOAST_CMD:-}" ]]; then
    "$FOLLOWUP_TOAST_CMD" "followup" "$(cat "$notice")"
  else
    source "$REPO_ROOT/scripts/lib/notify-windows-toast.sh"
    send_windows_toast "followup" "$(cat "$notice")"
  fi
  rm -f -- "$notice"
fi
echo "$(date): followup done"
