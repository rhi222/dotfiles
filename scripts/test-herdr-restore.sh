#!/bin/bash
# lib/herdr-restore.sh のユニットテスト
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/lib/herdr-restore.sh"

if [[ ! -f "$LIB" ]]; then
  echo "ERROR: $LIB が存在しません"
  exit 1
fi

# shellcheck source=lib/herdr-restore.sh
source "$LIB"

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
NVIM_DIR=""
CLAUDE_DIR=""
ALIVE=""

setup() {
  TEST_DIR=$(mktemp -d)
  NVIM_DIR="$TEST_DIR/herdr-nvim"
  CLAUDE_DIR="$TEST_DIR/herdr-claude"
  ALIVE="$TEST_DIR/alive"
  mkdir -p "$NVIM_DIR" "$CLAUDE_DIR"
  : >"$ALIVE"
}

teardown() {
  rm -rf "$TEST_DIR"
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected: [$expected]"
    echo "    actual  : [$actual]"
  fi
}

assert_ok() {
  local name="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@"; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (真であるべき)"
  fi
}

assert_ng() {
  local name="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (偽であるべき)"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  fi
}

nvim_marker() { printf '/tmp/proj\n' >"$NVIM_DIR/$1"; }
claude_marker() { printf '%s\n/tmp/proj\n%s\n' "$2" "$3" >"$CLAUDE_DIR/$1"; }

echo "test: workspace_of"
assert_eq "w5:p29 -> w5" "w5" "$(herdr_restore_workspace_of w5:p29)"
assert_eq "w6:p8V -> w6" "w6" "$(herdr_restore_workspace_of w6:p8V)"

echo "test: claude_command"
setup
touch "$TEST_DIR/t.jsonl"
claude_marker "w5:p1" "sess-1" "$TEST_DIR/t.jsonl"
assert_eq "transcript があれば resume" "claude --resume sess-1" "$(herdr_restore_claude_command "$CLAUDE_DIR/w5:p1")"
claude_marker "w5:p2" "sess-2" "$TEST_DIR/missing.jsonl"
assert_eq "transcript が無ければ素の claude" "claude" "$(herdr_restore_claude_command "$CLAUDE_DIR/w5:p2")"
claude_marker "w5:p3" "" ""
assert_eq "session_id が空なら素の claude" "claude" "$(herdr_restore_claude_command "$CLAUDE_DIR/w5:p3")"
teardown

echo "test: plan の並び順"
setup
touch "$TEST_DIR/t.jsonl"
printf 'w5:p1\nw5:p2\nw6:p1\nw6:p2\n' >"$ALIVE"
nvim_marker "w5:p1"
nvim_marker "w6:p1"
claude_marker "w5:p2" "sess-a" "$TEST_DIR/t.jsonl"
claude_marker "w6:p2" "sess-b" "$TEST_DIR/t.jsonl"
EXPECTED=$(printf 'nvim\tw5:p1\tnvim\nnvim\tw6:p1\tnvim\nclaude\tw5:p2\tclaude --resume sess-a\nclaude\tw6:p2\tclaude --resume sess-b')
assert_eq "nvim が先、各種別内はフォーカス中 workspace が先" "$EXPECTED" "$(herdr_restore_plan "$NVIM_DIR" "$CLAUDE_DIR" "$ALIVE" "w5")"
teardown

echo "test: 死んだペインは plan に入らない"
setup
printf 'w5:p1\n' >"$ALIVE"
nvim_marker "w5:p1"
nvim_marker "w5:p99"
assert_eq "生存ペインだけ" "$(printf 'nvim\tw5:p1\tnvim')" "$(herdr_restore_plan "$NVIM_DIR" "$CLAUDE_DIR" "$ALIVE" "w5")"
teardown

echo "test: prune_markers"
setup
printf 'w5:p1\n' >"$ALIVE"
nvim_marker "w5:p1"
nvim_marker "w5:p99"
herdr_restore_prune_markers "$NVIM_DIR" "$ALIVE"
assert_eq "生存ペインのマーカーは残る" "present" "$([[ -f "$NVIM_DIR/w5:p1" ]] && echo present || echo absent)"
assert_eq "死んだペインのマーカーは消える" "absent" "$([[ -f "$NVIM_DIR/w5:p99" ]] && echo present || echo absent)"
teardown

echo "test: alive が空なら何も消さない"
setup
: >"$ALIVE"
nvim_marker "w5:p1"
herdr_restore_prune_markers "$NVIM_DIR" "$ALIVE"
assert_eq "取得失敗時はマーカーを保持する" "present" "$([[ -f "$NVIM_DIR/w5:p1" ]] && echo present || echo absent)"
teardown

echo "test: pane_is_idle"
IDLE='{"result":{"process_info":{"foreground_processes":[{"cmdline":"/usr/bin/fish","pid":23983}],"shell_pid":23983}}}'
BUSY='{"result":{"process_info":{"foreground_processes":[{"cmdline":"nvim","pid":24497}],"shell_pid":23986}}}'
EMPTY='{"result":{}}'
assert_ok "素のシェルは idle" herdr_restore_pane_is_idle "$IDLE"
assert_ng "何か走っていれば idle でない" herdr_restore_pane_is_idle "$BUSY"
assert_ng "情報が取れなければ idle でない" herdr_restore_pane_is_idle "$EMPTY"

echo ""
echo "TOTAL=$TOTAL PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
