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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/cron-claude.sh"

# フラグファイルで有効化チェック
cron_require_flag "$HOME/.config/nippo-create-enabled"

# 平日のみ（NIPPO_CREATE_FORCE=1 でスキップ可能。テスト・手動実行用）
cron_weekday_only "${NIPPO_CREATE_FORCE:-0}"

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
# テンプレートを埋めるだけなので短い。始業時刻までに終わる必要がある
CLAUDE_TIMEOUT="${NIPPO_CREATE_TIMEOUT:-600}"
# パス解決は共有ライブラリに委ねる。ここで組み立てない。
# shellcheck source=lib/nippo-paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/nippo-paths.sh"
VAULT="$(nippo_vault)"
NIPPO_FILE="$(nippo_daily_file "$(date +%Y-%m-%d)")"
# 引数なしで呼ぶと、ファイルが無い場合は新規作成のみが走る（作業ログの追記は発生しない）
PROMPT="/nippo-add"
# nippo-add の allowed-tools に合わせて許可を最小化する
# Bash(source:*) と Bash(ghq:*) は skill が nippo-paths.sh を読むために要る。
# Bash(mkdir:*) は年/月ディレクトリを掘るために要る。
# cron は skill の frontmatter とは別に許可リストを持つので、ここを忘れると
# 平日8:00の自動実行が権限で落ちる。
# Bash(bash:*) は面談準備の起票（linear-interview-prep.sh）に要る。
# cron は skill の frontmatter とは別に許可リストを自前で持っているので、
# ここを忘れると手動の /nippo-add では動くのに 8:00 の自動実行だけ権限で落ちる
ALLOWED_TOOLS="Read,Write,Edit,Bash(date:*),Bash(ls:*),Bash(cat:*),Bash(wc:*),Bash(source:*),Bash(ghq:*),Bash(mkdir:*),Bash(bash:*),mcp__claude_ai_Google_Calendar__list_events"

if [[ "${NIPPO_CREATE_DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN: cd $VAULT && timeout $CLAUDE_TIMEOUT $CLAUDE_BIN -p \"$PROMPT\" --allowedTools \"$ALLOWED_TOOLS\""
  exit 0
fi

# 冪等性: 当日ファイルが既にあれば何もしない（手動作成済みの上書き・空ログ追記を防ぐ）
if [[ -f "$NIPPO_FILE" ]]; then
  echo "$(date): $NIPPO_FILE already exists, skip"
  exit 0
fi

cd "$VAULT"
cron_run_claude "日報ファイル作成" "$CLAUDE_TIMEOUT" "$CLAUDE_BIN" \
  -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS"
echo "$(date): nippo file created -> $NIPPO_FILE"
