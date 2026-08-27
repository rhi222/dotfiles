#!/bin/bash
# 日報ドラフト自動仕上げ（cron用ラッパー）
# 平日夕方に nippo-finalize スキルをヘッドレス実行し、日報ドラフトを仕上げる。
# 人間は生成結果をレビューするだけにする。
#
# crontab設定例:
#   30 18 * * 1-5 $HOME/scripts/nippo/draft-cron.sh >> $HOME/.nippo-draft-cron.log 2>&1
#
# 有効化: touch ~/.config/nippo-draft-enabled
# 無効化: rm ~/.config/nippo-draft-enabled
# 動作確認: NIPPO_DRAFT_DRY_RUN=1 NIPPO_DRAFT_FORCE=1 bash scripts/nippo/draft-cron.sh

set -euo pipefail

DOMAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$DOMAIN_DIR/../.." && pwd)"
source "$REPO_ROOT/internal/automation/cron-claude.sh"

# フラグファイルで有効化チェック
cron_require_flag "$HOME/.config/nippo-draft-enabled"

# 平日のみ（NIPPO_DRAFT_FORCE=1 でスキップ可能。テスト・手動実行用）
cron_weekday_only "${NIPPO_DRAFT_FORCE:-0}"

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
# GitHub活動の収集を含むが、対象は当日分だけなので短めでよい
CLAUDE_TIMEOUT="${NIPPO_DRAFT_TIMEOUT:-900}"
VAULT="${NIPPO_VAULT:-$HOME/Obsidian}"
PROMPT="/nippo-finalize"
# nippo-finalize の allowed-tools に合わせて許可を最小化する
# Bash(source:*) と Bash(ghq:*) は skill が nippo-paths.sh を読むために要る。
# Bash(mkdir:*) は年/月ディレクトリを掘るために要る。
# cron は skill の frontmatter とは別に許可リストを持つので、ここを忘れると
# 平日18:30の自動実行が権限で落ちる。
ALLOWED_TOOLS="Read,Write,Edit,Bash(date:*),Bash(ls:*),Bash(cat:*),Bash(wc:*),Bash(command:*),Bash(gh:*),Bash(jq:*),Bash(sort:*),Bash(paste:*),Bash(source:*),Bash(ghq:*),Bash(mkdir:*)"

if [[ "${NIPPO_DRAFT_DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN: cd $VAULT && timeout $CLAUDE_TIMEOUT $CLAUDE_BIN -p \"$PROMPT\" --allowedTools \"$ALLOWED_TOOLS\""
  exit 0
fi

cd "$VAULT"
cron_run_claude "日報ドラフト仕上げ" "$CLAUDE_TIMEOUT" "$CLAUDE_BIN" \
  -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS"
echo "$(date): nippo draft finalized"
