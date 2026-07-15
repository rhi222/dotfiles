#!/bin/bash
# 日報ファイル自動作成（cron用ラッパー）
# 平日朝に nippo-add スキルをヘッドレス実行し、当日の日報ファイルを新規作成する。
# テンプレート・今日の予定（カレンダー）・前日からの引き継ぎ・おすすめタスクを埋める。
# 人間は始業時にできあがった日報から書き始めるだけにする。
#
# crontab設定例:
#   0 8 * * 1-5 $HOME/scripts/nippo-create-cron.sh >> $HOME/.nippo-create-cron.log 2>&1
#
# 有効化: touch ~/.config/nippo-create-enabled
# 無効化: rm ~/.config/nippo-create-enabled
# 動作確認: NIPPO_CREATE_DRY_RUN=1 NIPPO_CREATE_FORCE=1 bash scripts/nippo-create-cron.sh

set -euo pipefail

# フラグファイルで有効化チェック
FLAG="$HOME/.config/nippo-create-enabled"
if [[ ! -f "$FLAG" ]]; then
  exit 0
fi

# 平日のみ（NIPPO_CREATE_FORCE=1 でスキップ可能。テスト・手動実行用）
DOW=$(date +%u)
if [[ "$DOW" -ge 6 && "${NIPPO_CREATE_FORCE:-0}" != "1" ]]; then
  exit 0
fi

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
VAULT="${NIPPO_VAULT:-/mnt/c/Users/ryohei_nishiyama/Desktop/Obsidian}"
NIPPO_FILE="$VAULT/02_Daily/nippo.$(date +%Y-%m-%d).md"
# 引数なしで呼ぶと、ファイルが無い場合は新規作成のみが走る（作業ログの追記は発生しない）
PROMPT="/nippo-add"
# nippo-add の allowed-tools に合わせて許可を最小化する
ALLOWED_TOOLS="Read,Write,Edit,Bash(date:*),Bash(ls:*),Bash(cat:*),Bash(wc:*),mcp__claude_ai_Google_Calendar__list_events"

if [[ "${NIPPO_CREATE_DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN: cd $VAULT && $CLAUDE_BIN -p \"$PROMPT\" --allowedTools \"$ALLOWED_TOOLS\""
  exit 0
fi

# 冪等性: 当日ファイルが既にあれば何もしない（手動作成済みの上書き・空ログ追記を防ぐ）
if [[ -f "$NIPPO_FILE" ]]; then
  echo "$(date): $NIPPO_FILE already exists, skip"
  exit 0
fi

cd "$VAULT"
"$CLAUDE_BIN" -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS"
echo "$(date): nippo file created -> $NIPPO_FILE"
