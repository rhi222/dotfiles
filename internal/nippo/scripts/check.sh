#!/bin/bash
# 日報状態チェッカー
# 日報の状態を検査し、問題があればメッセージをstdoutに出力してexit 1で終了する。
#
# 引数: stop | cron（呼び出し元コンテキスト）
#
# 環境変数（テスト用オーバーライド）:
#   NIPPO_DIR  - 日報ディレクトリ（デフォルト: ~/Obsidian/02_Daily）
#   NIPPO_NOW  - 現在時刻の上書き（例: "2026-03-09 14:00"）

set -euo pipefail

# 呼び出し元コンテキスト。stop は Claude Code の Stop フック、cron は定時実行。
CONTEXT="${1:-stop}"

# 機械可読な契約行。テストと将来の呼び出し側はこれ（stderr 最終行）を見る。
# stdout は通知本文なので、体裁を変えてもこの契約は壊れない。
# 消費者（notify-cron.sh / notify-windows.sh）は 2>/dev/null で捨てるため影響しない。
# 各チェックは発火した時点で即 exit する制御構造なので、HITS は常に単一コード。
report() { # $1=検査コード $2=人間向けメッセージ
  echo "$2"
  echo "nippo-check: CONTEXT=${CONTEXT} HITS=$1" >&2
  exit 1
}
# 何も発火しなかった（通知なし）。
clean_exit() {
  echo "nippo-check: CONTEXT=${CONTEXT} HITS=none" >&2
  exit 0
}

# パス解決は共有ライブラリに委ねる。ここで組み立てない。
# ghq ではなく自身の位置から相対で引くのは、このスクリプトが cron や Stop フックから
# 直接実行され、ghq が PATH に無い状態を踏みうるため。
DOMAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/paths.sh
source "$DOMAIN_DIR/lib/paths.sh"
NIPPO_DIR="$(nippo_root)"

# stop は応答が終わるたびに走るため、一日中真になり続ける低優先度チェック
# （陳腐化検知・未完了タスク件数）は cron 側だけで報告する。
# stop で出すのは、その場で手を動かすべき緊急度の高いものに限る。
# 未知のコンテキストは取りこぼしを避けるため cron 相当（全チェック）とする。
if [[ "$CONTEXT" == "stop" ]]; then
  LOW_PRIORITY_CHECKS=0
else
  LOW_PRIORITY_CHECKS=1
fi

# 現在時刻の取得（NIPPO_NOWでオーバーライド可能）
if [[ -n "${NIPPO_NOW:-}" ]]; then
  NOW="$NIPPO_NOW"
else
  NOW="$(date '+%Y-%m-%d %H:%M')"
fi

# 日付・時刻・曜日の取得
TODAY=$(echo "$NOW" | cut -d' ' -f1)
# 10# で base-10 強制パース（"08"→8, "00"→0）。sed 's/^0//' だと "00" が空文字になり [[ ]] が死ぬ
HOUR=$((10#$(echo "$NOW" | cut -d' ' -f2 | cut -d: -f1)))
DOW=$(date -d "$TODAY" +%u) # 1=月 ... 7=日

NIPPO_FILE="$(nippo_daily_file "$TODAY")"

# --- チェック1: 平日判定 ---
if [[ "$DOW" -ge 6 ]]; then
  clean_exit
fi

# --- チェック2: ファイル存在チェック ---
if [[ ! -f "$NIPPO_FILE" ]]; then
  if [[ "$HOUR" -ge 9 ]]; then
    report missing "📝 今日の日報がまだ作成されていません"
  fi
  clean_exit
fi

# --- チェック3: 未終了タイマー ---
# 🟢 start: に対応する 🔴 end: がないものを検出
started_tasks=()
while IFS= read -r line; do
  task_name="${line##*"🟢 start: "}"
  started_tasks+=("$task_name")
done < <(grep '🟢 start:' "$NIPPO_FILE" 2>/dev/null || true)

ended_tasks=()
while IFS= read -r line; do
  task_name="${line##*"🔴 end: "}"
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
    report open-timer "🟢 「${task}」が開始のまま未終了です"
  fi
done

# --- チェック4: 陳腐化検知（低優先度） ---
# 未完了タスク数を計算（チェック4と6で共用）
# grep -c はマッチ0件でexit 1を返すため、set -e防御として || fallback が必須
# 日報は /mnt/c (9p) 上にあり1ファイル操作あたり数秒かかるので、
# 結果を使わない stop では grep/stat 自体を走らせない
incomplete_count=0
if [[ "$LOW_PRIORITY_CHECKS" -eq 1 ]]; then
  incomplete_count=$(grep -cE '^\s*- \[[ -]\]' "$NIPPO_FILE" 2>/dev/null) || incomplete_count=0
fi

if [[ "$LOW_PRIORITY_CHECKS" -eq 1 && "$incomplete_count" -gt 0 ]]; then
  file_mtime=$(stat -c %Y "$NIPPO_FILE" 2>/dev/null || echo "0")
  if [[ -n "${NIPPO_NOW:-}" ]]; then
    now_epoch=$(date -d "$NIPPO_NOW" +%s 2>/dev/null || echo "0")
  else
    now_epoch=$(date +%s)
  fi
  elapsed_minutes=$(((now_epoch - file_mtime) / 60))

  if [[ "$elapsed_minutes" -ge 90 ]]; then
    report stale "⏰ 日報が${elapsed_minutes}分以上更新されていません（未完了: ${incomplete_count}件）"
  fi
fi

# --- チェック5: Finalize忘れ ---
if [[ "$HOUR" -ge 18 ]]; then
  if ! grep -q '^## Finalize:' "$NIPPO_FILE" 2>/dev/null; then
    report finalize "📊 日報のfinalize忘れていませんか？"
  fi
fi

# --- チェック6: 未完了タスク（低優先度） ---
if [[ "$LOW_PRIORITY_CHECKS" -eq 1 && "$incomplete_count" -gt 0 ]]; then
  report incomplete "📋 未完了タスク: ${incomplete_count}件"
fi

clean_exit
