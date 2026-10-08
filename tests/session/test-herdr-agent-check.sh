#!/bin/bash
# herdr-agent-check.sh は、agent が動いているのに session identity を持たない pane を数える。
# hook の報告が黙って失敗し続けると、次の restart でその agent は復元されない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$REPO_ROOT/scripts/session/herdr-agent-check.sh"

PASS=0
FAIL=0
TOTAL=0
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
BIN="$TEST_DIR/herdr"
export HERDR_TEST_OUTPUT="$TEST_DIR/pane-list.json"

# pane list の応答を file から返し、file が無ければ server 停止として失敗する。
printf '#!/bin/sh\n[ -f "$HERDR_TEST_OUTPUT" ] || exit 1\ncat "$HERDR_TEST_OUTPUT"\n' >"$BIN"
chmod +x "$BIN"

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

run_check() {
  HERDR_BIN="$BIN" bash "$CHECK" 2>&1
}

summary() {
  printf '%s\n' "$1" | grep '^herdr-agent-check:'
}

echo "test: session を持たない agent pane を数える"
cat >"$HERDR_TEST_OUTPUT" <<'EOF'
{"result":{"panes":[
 {"pane_id":"w1:p1","agent":"claude","cwd":"/repo/a","agent_session":{"value":"s-1"}},
 {"pane_id":"w1:p2","agent":"claude","cwd":"/repo/b","agent_session":null},
 {"pane_id":"w2:p3","agent":"codex","cwd":"/repo/c"},
 {"pane_id":"w2:p4","cwd":"/repo/d"}
]}}
EOF
out=$(run_check)
status=$?
assert_eq "終了コード 0" "0" "$status"
assert_eq "サマリ行" "herdr-agent-check: UNREPORTED=2" "$(summary "$out")"
assert_eq "未報告 pane を列挙する" "yes" \
  "$(grep -q 'w1:p2.*claude.*/repo/b' <<<"$out" && grep -q 'w2:p3.*codex.*/repo/c' <<<"$out" && echo yes || echo no)"
assert_eq "報告済み pane と shell は出さない" "no" \
  "$(grep -qE 'w1:p1|w2:p4' <<<"$out" && echo yes || echo no)"

echo "test: 全て報告済みなら 0 件"
echo '{"result":{"panes":[{"pane_id":"w1:p1","agent":"claude","agent_session":{"value":"s-1"}}]}}' \
  >"$HERDR_TEST_OUTPUT"
assert_eq "サマリ行" "herdr-agent-check: UNREPORTED=0" "$(summary "$(run_check)")"

echo "test: server が動いていなければ skip する"
rm -f "$HERDR_TEST_OUTPUT"
out=$(run_check)
status=$?
assert_eq "終了コード 0" "0" "$status"
assert_eq "件数を出さない" "" "$(summary "$out")"

echo ""
echo "TOTAL=$TOTAL PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
