#!/bin/bash
# Claude / Codex hook は Herdr 内のみで現在 pane の session identity を報告し、
# 遅延した Codex hook が別 thread の identity を上書きしない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_HOOK="$REPO_ROOT/.config/claude/hooks/herdr-agent-session.sh"
CODEX_HOOK="$REPO_ROOT/.config/codex/hooks/herdr-agent-session.sh"

PASS=0
FAIL=0
TOTAL=0
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
LOG="$TEST_DIR/herdr.log"
BIN="$TEST_DIR/herdr"

printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"$HERDR_TEST_LOG"\n' >"$BIN"
chmod +x "$BIN"
export HERDR_TEST_LOG="$LOG"

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

invoke() {
  local hook="$1" payload="$2"
  HERDR_ENV=1 HERDR_PANE_ID=w5:p29 HERDR_BIN_PATH="$BIN" "$hook" <<<"$payload"
}

echo "test: Herdr の外では報告しない"
HERDR_ENV=0 HERDR_PANE_ID=w5:p29 HERDR_BIN_PATH="$BIN" \
  "$CLAUDE_HOOK" <<<'{"session_id":"claude-1"}'
assert_eq "CLI を呼ばない" "absent" "$([[ -e "$LOG" ]] && echo present || echo absent)"

echo "test: Claude session を報告する"
invoke "$CLAUDE_HOOK" '{"session_id":"claude-1","transcript_path":"/tmp/claude.jsonl"}'
assert_eq "session id と transcript path" \
  "pane report-agent-session w5:p29 --source herdr:claude --agent claude" \
  "$(awk 'NR==1 {print $1, $2, $3, $4, $5, $6, $7}' "$LOG")"
grep -q -- '--agent-session-id claude-1' "$LOG"
assert_eq "transcript path を含む" "yes" \
  "$(grep -q -- '--agent-session-path /tmp/claude.jsonl' "$LOG" && echo yes || echo no)"

echo "test: Codex session を報告する"
: >"$LOG"
CODEX_THREAD_ID=codex-1 invoke "$CODEX_HOOK" \
  '{"session_id":"codex-1","transcript_path":"/tmp/codex.jsonl"}'
assert_eq "Codex source と session id" "yes" \
  "$(grep -q -- '--source herdr:codex --agent codex .*--agent-session-id codex-1' "$LOG" && echo yes || echo no)"

echo "test: 別 thread から遅れて届いた Codex hook は無視する"
: >"$LOG"
CODEX_THREAD_ID=codex-new invoke "$CODEX_HOOK" \
  '{"session_id":"codex-old","transcript_path":"/tmp/codex.jsonl"}'
assert_eq "CLI を呼ばない" "empty" "$([[ -s "$LOG" ]] && echo present || echo empty)"

echo ""
echo "TOTAL=$TOTAL PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
