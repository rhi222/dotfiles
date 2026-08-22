#!/bin/bash
# Slackリアクション起票（cron用ラッパー）
# 平日朝に linear-slack-sweep スキルをヘッドレス実行し、
# :nishiyama_todo: を押したメッセージを Linear Triage へ起票する。
#
# crontab設定例:
#   10 8 * * 1-5 $HOME/scripts/linear-slack-sweep-cron.sh >> $HOME/.linear-slack-sweep.log 2>&1
#
# 有効化: touch ~/.config/linear-slack-sweep-enabled
# 無効化: rm ~/.config/linear-slack-sweep-enabled
# 動作確認: LINEAR_SLACK_SWEEP_DRY_RUN=1 LINEAR_SLACK_SWEEP_FORCE=1 bash scripts/linear-slack-sweep-cron.sh
#
# 【重要】Slackへは一切書き込まない。--allowedTools に読み取り2つしか入れないことが
# その担保になっている。test-linear-slack-sweep-cron.sh がこれを検証する。
set -euo pipefail

# ~/scripts は dotfiles/scripts へのsymlinkなので readlink -f で実体を解決する。
# 解決しないと repo root が $HOME になり、skillもスクリプトも見つからない
DOMAIN_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
REPO_ROOT="$(cd "$DOMAIN_DIR/../.." && pwd)"
source "$REPO_ROOT/internal/automation/cron-claude.sh"

cron_require_flag "$HOME/.config/linear-slack-sweep-enabled"

# 平日のみ（LINEAR_SLACK_SWEEP_FORCE=1 でスキップ可能。テスト・手動実行用）
cron_weekday_only "${LINEAR_SLACK_SWEEP_FORCE:-0}"

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
REPO="${LINEAR_SLACK_SWEEP_REPO:-$REPO_ROOT}"
# スレを読んで要約する仕事なので、日報ドラフト（900秒）と同じ桁で足りる
CLAUDE_TIMEOUT="${LINEAR_SLACK_SWEEP_TIMEOUT:-900}"
PROMPT="/linear-slack-sweep"
# skill の allowed-tools に合わせて許可を最小化する。
# Slackは読み取り2つのみ。書き込み系は意図的に入れていない
ALLOWED_TOOLS="Bash(bash:*),Bash(ghq:*),mcp__claude_ai_Slack__slack_search_public_and_private,mcp__claude_ai_Slack__slack_read_thread"

if [[ "${LINEAR_SLACK_SWEEP_DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN: cd $REPO && timeout $CLAUDE_TIMEOUT $CLAUDE_BIN -p \"$PROMPT\" --allowedTools \"$ALLOWED_TOOLS\""
  exit 0
fi

cd "$REPO"
cron_run_claude "Slackスタンプ起票" "$CLAUDE_TIMEOUT" "$CLAUDE_BIN" \
  -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS"
echo "$(date): linear-slack-sweep done"
