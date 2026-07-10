#!/bin/bash
# nippo-draft-cron.sh のテスト
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/nippo-draft-cron.sh"
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
touch "$tmp_home2/.config/nippo-draft-enabled"
out2=$(HOME="$tmp_home2" NIPPO_DRAFT_DRY_RUN=1 NIPPO_DRAFT_FORCE=1 bash "$SCRIPT" 2>&1)
check "DRY_RUNで実行内容を表示する" grep -q "DRY_RUN" <<<"$out2"
check "DRY_RUNでnippo-finalizeを呼ぶ予定が表示される" grep -q "nippo-finalize" <<<"$out2"

# 3. DRY_RUNでclaude本体が呼ばれていないこと（存在しないバイナリを指定しても成功する）
out3=$(HOME="$tmp_home2" NIPPO_DRAFT_DRY_RUN=1 NIPPO_DRAFT_FORCE=1 CLAUDE_BIN=/nonexistent/claude bash "$SCRIPT" 2>&1)
check "DRY_RUNではclaudeを実行しない" grep -q "DRY_RUN" <<<"$out3"

rm -rf "$tmp_home1" "$tmp_home2"

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
