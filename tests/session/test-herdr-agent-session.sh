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

echo "test: HERDR_BIN_PATH が消えていたら PATH 上の herdr で報告する"
# mise upgrade は旧版の install dir を消す。稼働中の server が配った pane の
# HERDR_BIN_PATH はその消えた path を指したままになる。
: >"$LOG"
for hook in "$CLAUDE_HOOK" "$CODEX_HOOK"; do
  CODEX_THREAD_ID=s-1 HERDR_ENV=1 HERDR_PANE_ID=w5:p29 \
    HERDR_BIN_PATH="$TEST_DIR/removed/herdr" PATH="$TEST_DIR:$PATH" \
    "$hook" <<<'{"session_id":"s-1","transcript_path":"/tmp/s.jsonl"}'
done
assert_eq "Claude と Codex の両方が報告する" "2" \
  "$(grep -c -- '--agent-session-id s-1' "$LOG")"

echo "test: Claude の SessionStart source を渡す"
# /clear で session が替わったとき、source が無いと Herdr は新 ID を拒否する。
: >"$LOG"
invoke "$CLAUDE_HOOK" '{"session_id":"claude-2","source":"clear"}'
assert_eq "--session-start-source clear を含む" "yes" \
  "$(grep -q -- '--session-start-source clear' "$LOG" && echo yes || echo no)"

echo ""
echo "TOTAL=$TOTAL PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
