#!/bin/bash
# linear-slack-sweep-cron.sh のテスト
#
# 重要: --allowedTools に Slack の書き込み系が含まれていないことを検証する。
# 「Slackへ書き戻さない」の担保が許可リストそのものなので、ここが唯一の防壁になる。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/linear-slack-sweep-cron.sh"
pass=0
fail=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "NG: $desc"
    fail=$((fail + 1))
  fi
}

# 1. フラグなし → 何もせず正常終了
tmp1=$(mktemp -d)
out1=$(HOME="$tmp1" bash "$SCRIPT" 2>&1)
check "フラグなしで静かにスキップする" test -z "$out1"

# 2. フラグあり + DRY_RUN → 実行予定を表示
tmp2=$(mktemp -d)
mkdir -p "$tmp2/.config"
touch "$tmp2/.config/linear-slack-sweep-enabled"
out2=$(HOME="$tmp2" LINEAR_SLACK_SWEEP_DRY_RUN=1 LINEAR_SLACK_SWEEP_FORCE=1 bash "$SCRIPT" 2>&1)
check "DRY_RUNで実行内容を表示する" grep -q "DRY_RUN" <<<"$out2"
check "linear-slack-sweep skillを呼ぶ" grep -q "/linear-slack-sweep" <<<"$out2"

# 3. allowedTools の中身
check "Slack検索を許可する" grep -q "slack_search_public_and_private" <<<"$out2"
check "スレ読み取りを許可する" grep -q "slack_read_thread" <<<"$out2"
check "スクリプト実行を許可する" grep -q 'Bash(scripts/linear-slack-sweep.sh:\*)' <<<"$out2"
check "dateを許可する（after:の日付計算用）" grep -q 'Bash(date:\*)' <<<"$out2"

# 3b. timeout が掛かっている（headless実行は誰も見ていないのでハングを残さない）
check "timeoutを噛ませる" grep -q "timeout " <<<"$out2"
out2b=$(HOME="$tmp2" LINEAR_SLACK_SWEEP_DRY_RUN=1 LINEAR_SLACK_SWEEP_FORCE=1 \
  LINEAR_SLACK_SWEEP_TIMEOUT=42 bash "$SCRIPT" 2>&1)
check "timeoutを環境変数で上書きできる" grep -q "timeout 42" <<<"$out2b"

# 4. Slackへの書き込み系が許可されていない（これが「書き戻さない」の担保）
for t in slack_send_message slack_send_message_draft slack_schedule_message \
  slack_create_canvas slack_update_canvas; do
  check "書き込み系を許可しない: $t" test "$(grep -c "$t" <<<"$out2")" -eq 0
done

# 5. DRY_RUNではclaude本体を実行しない（存在しないバイナリでも成功する）
out5=$(HOME="$tmp2" LINEAR_SLACK_SWEEP_DRY_RUN=1 LINEAR_SLACK_SWEEP_FORCE=1 \
  CLAUDE_BIN=/nonexistent/claude bash "$SCRIPT" 2>&1)
check "DRY_RUNではclaudeを実行しない" grep -q "DRY_RUN" <<<"$out5"

# 6. リポジトリのパス解決がsymlink越しでも壊れない
#    ~/scripts は dotfiles/scripts へのsymlinkなので、readlink -f で解決する必要がある
ln -s "$SCRIPT_DIR" "$tmp2/scripts"
out6=$(HOME="$tmp2" LINEAR_SLACK_SWEEP_DRY_RUN=1 LINEAR_SLACK_SWEEP_FORCE=1 \
  bash "$tmp2/scripts/linear-slack-sweep-cron.sh" 2>&1)
check "symlink越しでもリポジトリを解決する" grep -q "$(dirname "$SCRIPT_DIR")" <<<"$out6"

echo "---"
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
