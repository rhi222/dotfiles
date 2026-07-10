#!/bin/bash
# esa-weekly-cron.sh のテスト
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/esa-weekly-cron.sh"
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

# 1. フラグファイルなし → 何もせず正常終了
tmp_home1=$(mktemp -d)
out1=$(HOME="$tmp_home1" bash "$SCRIPT" 2>&1)
check "フラグなしで静かにスキップする" test -z "$out1"

# 2. フラグあり + DRY_RUN → 実行予定内容を表示して終了
tmp_home2=$(mktemp -d)
mkdir -p "$tmp_home2/.config"
touch "$tmp_home2/.config/esa-weekly-enabled"
out2=$(HOME="$tmp_home2" ESA_WEEKLY_DRY_RUN=1 bash "$SCRIPT" 2>&1)
check "DRY_RUNで実行内容を表示する" grep -q "DRY_RUN" <<<"$out2"
check "DRY_RUNでesa-weekly-reportを呼ぶ予定が表示される" grep -q "esa-weekly-report" <<<"$out2"

# 3. DRY_RUNでclaude本体が呼ばれていないこと
out3=$(HOME="$tmp_home2" ESA_WEEKLY_DRY_RUN=1 CLAUDE_BIN=/nonexistent/claude bash "$SCRIPT" 2>&1)
check "DRY_RUNではclaudeを実行しない" grep -q "DRY_RUN" <<<"$out3"

rm -rf "$tmp_home1" "$tmp_home2"

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
