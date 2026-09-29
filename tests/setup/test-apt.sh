#!/bin/bash
# apt setupはgit-core PPAを登録してからapt updateし、宣言済みpackageを導入する。
# PATH先頭のsudo stubで呼び出しを記録し、実aptは変更しない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETUP="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/setup/apt.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"
SUDO_LOG="$TEST_DIR/sudo.log"
cat >"$TEST_DIR/bin/sudo" <<STUB
#!/bin/bash
echo "\$*" >>"$SUDO_LOG"
STUB
chmod +x "$TEST_DIR/bin/sudo"

PASS=0
FAIL=0
check() {
  if [[ $2 -eq 0 ]]; then
    echo "PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
  fi
}

PATH="$TEST_DIR/bin:$PATH" bash "$SETUP" >/dev/null 2>&1
status=$?

ppa_line=$(grep -n 'add-apt-repository .*ppa:git-core/ppa' "$SUDO_LOG" | head -1 | cut -d: -f1)
update_line=$(grep -n '^apt update' "$SUDO_LOG" | head -1 | cut -d: -f1)

[[ $status -eq 0 ]]
check "終了コード0" $?
[[ -n $ppa_line ]]
check "git-core PPAを登録する" $?
[[ -n $ppa_line && -n $update_line && $ppa_line -lt $update_line ]]
check "PPA登録はapt updateより前" $?
grep -qE '^apt install -y .*\bgit\b' "$SUDO_LOG"
check "gitをinstall対象に含む" $?

echo "結果: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
