#!/bin/bash
# .config/claude/hooks/herdr-claude-marker.sh のユニットテスト
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../.config/claude/hooks/herdr-claude-marker.sh"

if [[ ! -x "$HOOK" ]]; then
  echo "ERROR: $HOOK が実行可能ではありません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
MARKER_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  export XDG_STATE_HOME="$TEST_DIR/state"
  MARKER_DIR="$XDG_STATE_HOME/herdr-claude"
}

teardown() {
  rm -rf "$TEST_DIR"
  unset XDG_STATE_HOME
  unset HERDR_PANE_ID
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
    echo "    expected: $expected"
    echo "    actual  : $actual"
  fi
}

payload() {
  # $1 session_id, $2 transcript_path
  printf '{"session_id":"%s","cwd":"/tmp/proj","transcript_path":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1" "$2"
}

echo "test: HERDR_PANE_ID が無いときは何も作らない"
setup
unset HERDR_PANE_ID
payload sess-1 /tmp/t1.jsonl | "$HOOK" start
assert_eq "マーカーディレクトリが作られない" "absent" "$([[ -d "$MARKER_DIR" ]] && echo present || echo absent)"
teardown

echo "test: start でマーカーが3行で書かれる"
setup
export HERDR_PANE_ID="w5:p29"
payload sess-1 /tmp/t1.jsonl | "$HOOK" start
assert_eq "1行目は session_id" "sess-1" "$(awk 'NR==1' "$MARKER_DIR/w5:p29")"
assert_eq "2行目は cwd" "/tmp/proj" "$(awk 'NR==2' "$MARKER_DIR/w5:p29")"
assert_eq "3行目は transcript_path" "/tmp/t1.jsonl" "$(awk 'NR==3' "$MARKER_DIR/w5:p29")"
teardown

echo "test: 2回目の start が上書きする"
setup
export HERDR_PANE_ID="w5:p29"
payload sess-1 /tmp/t1.jsonl | "$HOOK" start
payload sess-2 /tmp/t2.jsonl | "$HOOK" start
assert_eq "session_id が更新される" "sess-2" "$(awk 'NR==1' "$MARKER_DIR/w5:p29")"
teardown

echo "test: end でマーカーが消える"
setup
export HERDR_PANE_ID="w5:p29"
payload sess-1 /tmp/t1.jsonl | "$HOOK" start
"$HOOK" end </dev/null
assert_eq "マーカーが削除される" "absent" "$([[ -f "$MARKER_DIR/w5:p29" ]] && echo present || echo absent)"
teardown

echo "test: session_id が空なら書かない"
setup
export HERDR_PANE_ID="w5:p29"
payload "" /tmp/t1.jsonl | "$HOOK" start
assert_eq "マーカーが作られない" "absent" "$([[ -f "$MARKER_DIR/w5:p29" ]] && echo present || echo absent)"
teardown

echo ""
echo "TOTAL=$TOTAL PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
