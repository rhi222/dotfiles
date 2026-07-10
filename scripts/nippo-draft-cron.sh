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
VAULT="${NIPPO_VAULT:-/mnt/c/Users/ryohei_nishiyama/Desktop/Obsidian}"
PROMPT="/nippo-finalize"
# nippo-finalize の allowed-tools に合わせて許可を最小化する
ALLOWED_TOOLS="Read,Write,Edit,Bash(date:*),Bash(ls:*),Bash(cat:*),Bash(wc:*)"

if [[ "${NIPPO_DRAFT_DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN: cd $VAULT && $CLAUDE_BIN -p \"$PROMPT\" --allowedTools \"$ALLOWED_TOOLS\""
  exit 0
fi

cd "$VAULT"
"$CLAUDE_BIN" -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS"
echo "$(date): nippo draft finalized"
