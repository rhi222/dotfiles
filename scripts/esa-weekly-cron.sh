#!/bin/bash
# esa週次レポートドラフト自動生成（cron用ラッパー）
# 金曜夕方に esa-weekly-report スキルをヘッドレス実行し、
# 部長会向けレポートのドラフトをObsidianに出力する。
#
# crontab設定例:
#   0 16 * * 5 $HOME/scripts/esa-weekly-cron.sh >> $HOME/.esa-weekly-cron.log 2>&1
#
# 有効化: touch ~/.config/esa-weekly-enabled
# 無効化: rm ~/.config/esa-weekly-enabled
# 動作確認: ESA_WEEKLY_DRY_RUN=1 bash scripts/esa-weekly-cron.sh

set -euo pipefail

# フラグファイルで有効化チェック
FLAG="$HOME/.config/esa-weekly-enabled"
if [[ ! -f "$FLAG" ]]; then
  exit 0
fi

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
OUT_DIR="${ESA_WEEKLY_OUT:-/mnt/c/Users/ryohei_nishiyama/Desktop/Obsidian/05_Organization/Buchokai}"
OUT_FILE="$OUT_DIR/weekly-draft-$(date +%Y-%m-%d).md"
PROMPT="/esa-weekly-report 結果は $OUT_FILE に保存して。投稿はせずファイル出力のみ"

if [[ "${ESA_WEEKLY_DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN: $CLAUDE_BIN -p \"$PROMPT\""
  exit 0
fi

"$CLAUDE_BIN" -p "$PROMPT"
echo "$(date): esa weekly report draft -> $OUT_FILE"
