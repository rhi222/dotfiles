#!/bin/bash
# bootstrapはHerdr公式のClaude / Codex integrationを入れる。
# 入れないと、新端末ではagentのsession IDがHerdrへ報告されず、restartで会話が戻らない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP_IMPLEMENTATION="$REPO_ROOT/internal/bootstrap/setup.sh"

pass=0
fail=0
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "NG: $desc"
    echo "    expected: [$expected]"
    echo "    actual  : [$actual]"
    fail=$((fail + 1))
  fi
}

run_setup() {
  # shellcheck disable=SC1090
  PATH="$1" bash -c 'source "$0" && setup_herdr_integrations' "$BOOTSTRAP_IMPLEMENTATION" 2>&1
}

STUB_BIN="$TEST_DIR/bin"
mkdir -p "$STUB_BIN"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/herdr.log"\n' "$TEST_DIR" >"$STUB_BIN/herdr"
chmod +x "$STUB_BIN/herdr"

echo "test: Claude と Codex の integration を入れる"
run_setup "$STUB_BIN:$PATH" >/dev/null
assert_eq "install の呼び出し" \
  "integration install claude
integration install codex" \
  "$(cat "$TEST_DIR/herdr.log")"

echo "test: herdr が無ければ警告して成功扱いにする"
exit_code=0
output=$(run_setup "/usr/bin:/bin") || exit_code=$?
assert_eq "終了コード 0" "0" "$exit_code"
assert_eq "復旧手順を出す" "yes" \
  "$(grep -q 'herdr integration install' <<<"$output" && echo yes || echo no)"

echo ""
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
