#!/bin/bash
# Linearに貼ったSlackスレの動きのまとめ（cron用ラッパー）
# 対象をLinearから機械的に取り出し、followup スキル（Haiku）に各スレの最新発言を書き写させ、
# 🆕があればWindows toastを出す。
#
# crontab設定例（slack-sweepの20分後）:
#   30 10,13,17 * * 1-5 $HOME/scripts/followup/digest-cron.sh >> $HOME/.followup-cron.log 2>&1
#
# 有効化: touch ~/.config/followup-enabled
# 無効化: rm ~/.config/followup-enabled
# 動作確認: FOLLOWUP_DRY_RUN=1 FOLLOWUP_FORCE=1 bash scripts/followup/digest-cron.sh
#
# 【重要】Slackへは一切書き込まない。--allowedTools にスレの読み取りとdotctlしか入れないことが
# その担保になっている。tests/followup/test-digest-cron.sh がこれを検証する。
set -euo pipefail

DOMAIN_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
REPO_ROOT="$(cd "$DOMAIN_DIR/../.." && pwd)"
source "$REPO_ROOT/internal/automation/cron-claude.sh"

cron_require_flag "$HOME/.config/followup-enabled"
cron_weekday_only "${FOLLOWUP_FORCE:-0}"

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
STATE_DIR="${FOLLOWUP_STATE_DIR:-$HOME/.local/state/followup}"
TARGETS_CMD="${FOLLOWUP_TARGETS_CMD:-$REPO_ROOT/scripts/followup/targets.sh}"
CLAUDE_TIMEOUT="${FOLLOWUP_TIMEOUT:-300}"
# スレを読んで書き写すだけで判断しないので、軽いモデルで足りる
MODEL="haiku"
# skill の allowed-tools と一致させる。書き込み系とSlack検索は意図的に入れていない
# Slack本文（他人の発言）を読むので、dotctlもapplyだけに絞る
ALLOWED_TOOLS="Bash(dotctl followup apply:*),mcp__claude_ai_Slack__slack_read_thread,mcp__claude_ai_Slack__slack_read_user_profile"

if [[ "${FOLLOWUP_DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN: cd $REPO_ROOT && $TARGETS_CMD | timeout $CLAUDE_TIMEOUT $CLAUDE_BIN -p \"/followup <対象>\" --model $MODEL --allowedTools \"$ALLOWED_TOOLS\""
  exit 0
fi

cd "$REPO_ROOT"
# cron の PATH には ~/.local/bin（dotctl・claude の置き場）が無いことがある
export PATH="$HOME/.local/bin:$PATH"
# dotctl が書く状態ディレクトリを cron 側と揃える
export FOLLOWUP_STATE_DIR="$STATE_DIR"
# 対象抽出が失敗したら claude を呼ばない（set -e で止まる）
targets=$("$TARGETS_CMD")
before=$(stat -c %Y "$STATE_DIR/state.json" 2>/dev/null || echo 0)
cron_run_claude "followup" "$CLAUDE_TIMEOUT" "$CLAUDE_BIN" \
  -p "/followup $targets" --model "$MODEL" --allowedTools "$ALLOWED_TOOLS"

# skillが途中で諦めるとclaudeは成功で終わるので、applyされたかを状態ファイルで確かめる
after=$(stat -c %Y "$STATE_DIR/state.json" 2>/dev/null || echo 0)
if [[ "$after" == "$before" ]]; then
  echo "$(date): followup: applyされなかった（スレの読み取り失敗など）" >&2
  exit 1
fi

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
