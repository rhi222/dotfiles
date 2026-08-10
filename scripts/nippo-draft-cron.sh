#!/bin/bash
# 日報ドラフト自動仕上げ（cron用ラッパー）
# 平日夕方に nippo-finalize スキルをヘッドレス実行し、日報ドラフトを仕上げる。
# 人間は生成結果をレビューするだけにする。
#
# crontab設定例:
#   30 18 * * 1-5 $HOME/scripts/nippo-draft-cron.sh >> $HOME/.nippo-draft-cron.log 2>&1
#
# 有効化: touch ~/.config/nippo-draft-enabled
# 無効化: rm ~/.config/nippo-draft-enabled
# 動作確認: NIPPO_DRAFT_DRY_RUN=1 NIPPO_DRAFT_FORCE=1 bash scripts/nippo-draft-cron.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/cron-claude.sh"

# フラグファイルで有効化チェック
FLAG="$HOME/.config/nippo-draft-enabled"
if [[ ! -f "$FLAG" ]]; then
  exit 0
fi

# 平日のみ（NIPPO_DRAFT_FORCE=1 でスキップ可能。テスト・手動実行用）
DOW=$(date +%u)
if [[ "$DOW" -ge 6 && "${NIPPO_DRAFT_FORCE:-0}" != "1" ]]; then
  exit 0
fi

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
# GitHub活動の収集を含むが、対象は当日分だけなので短めでよい
CLAUDE_TIMEOUT="${NIPPO_DRAFT_TIMEOUT:-900}"
VAULT="${NIPPO_VAULT:-$HOME/Obsidian}"
PROMPT="/nippo-finalize"
# nippo-finalize の allowed-tools に合わせて許可を最小化する
ALLOWED_TOOLS="Read,Write,Edit,Bash(date:*),Bash(ls:*),Bash(cat:*),Bash(wc:*),Bash(command:*),Bash(gh:*),Bash(jq:*),Bash(sort:*),Bash(paste:*)"

if [[ "${NIPPO_DRAFT_DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN: cd $VAULT && timeout $CLAUDE_TIMEOUT $CLAUDE_BIN -p \"$PROMPT\" --allowedTools \"$ALLOWED_TOOLS\""
  exit 0
fi

cd "$VAULT"
cron_run_claude "日報ドラフト仕上げ" "$CLAUDE_TIMEOUT" "$CLAUDE_BIN" \
  -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS"
echo "$(date): nippo draft finalized"
