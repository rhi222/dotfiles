#!/bin/bash
# 日報状態チェッカー
# 日報の状態を検査し、問題があればメッセージをstdoutに出力してexit 1で終了する。
#
# 引数: stop | cron（呼び出し元コンテキスト）
#
# 環境変数（テスト用オーバーライド）:
#   NIPPO_DIR  - 日報ディレクトリ（デフォルト: ~/Obsidian/02_Daily）
#   NIPPO_NOW  - 現在時刻の上書き（例: "2026-03-09 14:00"）

set -uo pipefail

CONTEXT="${1:-stop}"
NIPPO_DIR="${NIPPO_DIR:-$HOME/Obsidian/02_Daily}"

# 現在時刻の取得（NIPPO_NOWでオーバーライド可能）
if [[ -n "${NIPPO_NOW:-}" ]]; then
  NOW="$NIPPO_NOW"
else
  NOW="$(date '+%Y-%m-%d %H:%M')"
fi

# 日付・時刻・曜日の取得
TODAY=$(echo "$NOW" | cut -d' ' -f1)
HOUR=$(echo "$NOW" | cut -d' ' -f2 | cut -d: -f1 | sed 's/^0//')
DOW=$(date -d "$TODAY" +%u)  # 1=月 ... 7=日

NIPPO_FILE="$NIPPO_DIR/nippo.${TODAY}.md"

# --- チェック1: 平日判定 ---
if [[ "$DOW" -ge 6 ]]; then
  exit 0
fi

# --- チェック2: ファイル存在チェック ---
if [[ ! -f "$NIPPO_FILE" ]]; then
  if [[ "$HOUR" -ge 9 ]]; then
    echo "📝 今日の日報がまだ作成されていません"
    exit 1
  fi
  exit 0
fi

# --- チェック3: 未終了タイマー ---
# 🟢 start: に対応する 🔴 end: がないものを検出
started_tasks=()
while IFS= read -r line; do
  task_name=$(echo "$line" | sed 's/.*🟢 start: //')
  started_tasks+=("$task_name")
done < <(grep '🟢 start:' "$NIPPO_FILE" 2>/dev/null || true)

ended_tasks=()
while IFS= read -r line; do
  task_name=$(echo "$line" | sed 's/.*🔴 end: //')
  ended_tasks+=("$task_name")
done < <(grep '🔴 end:' "$NIPPO_FILE" 2>/dev/null || true)

for task in "${started_tasks[@]}"; do
  found=false
  for ended in "${ended_tasks[@]}"; do
    if [[ "$task" == "$ended" ]]; then
      found=true
      break
    fi
  done
  if [[ "$found" == false ]]; then
    echo "🟢 「${task}」が開始のまま未終了です"
    exit 1
  fi
done

# --- チェック4: 陳腐化検知 ---
# 未完了タスク数を計算（チェック4と6で共用）
incomplete_count=$(grep -cE '^\s*- \[[ -]\]' "$NIPPO_FILE" 2>/dev/null) || incomplete_count=0

if [[ "$incomplete_count" -gt 0 ]]; then
  file_mtime=$(stat -c %Y "$NIPPO_FILE" 2>/dev/null || echo "0")
  if [[ -n "${NIPPO_NOW:-}" ]]; then
    now_epoch=$(date -d "$NIPPO_NOW" +%s 2>/dev/null || echo "0")
  else
    now_epoch=$(date +%s)
  fi
  elapsed_minutes=$(( (now_epoch - file_mtime) / 60 ))

  if [[ "$elapsed_minutes" -ge 90 ]]; then
    echo "⏰ 日報が${elapsed_minutes}分以上更新されていません（未完了: ${incomplete_count}件）"
    exit 1
  fi
fi

# --- チェック5: Finalize忘れ ---
if [[ "$HOUR" -ge 18 ]]; then
  if ! grep -q '^## Finalize:' "$NIPPO_FILE" 2>/dev/null; then
    echo "📊 日報のfinalize忘れていませんか？"
    exit 1
  fi
fi

# --- チェック6: 未完了タスク ---
if [[ "$incomplete_count" -gt 0 ]]; then
  echo "📋 未完了タスク: ${incomplete_count}件"
  exit 1
fi

exit 0
