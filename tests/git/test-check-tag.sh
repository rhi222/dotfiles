#!/bin/bash
# scripts/git/check-tag.sh のrepo解決とタグ比較を検査する。
#
# **ghq は PATH 上の stub へ差し替える。** 実 ghq root を引くと利用者の手元の
# repository 構成で結果が変わるので、mktemp 下に作った repository だけを返す。
# git fetch --tags は remote が無ければ黙って失敗し、スクリプトは握り潰す。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK_TAG="$REPO_ROOT/scripts/git/check-tag.sh"

PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok   $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "         expected: $expected"
    echo "         actual  : $actual"
  fi
}

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

REPO="$TEST_DIR/example.com/example-org/example-repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
echo one >"$REPO/a.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -qm one
git -C "$REPO" tag same-a
git -C "$REPO" tag same-b
echo two >>"$REPO/a.txt"
git -C "$REPO" commit -qam two
git -C "$REPO" tag later

mkdir -p "$TEST_DIR/bin"
cat >"$TEST_DIR/bin/ghq" <<STUB
#!/bin/bash
printf '%s\n' "$REPO"
STUB
chmod +x "$TEST_DIR/bin/ghq"

run() {
  env PATH="$TEST_DIR/bin:$PATH" bash "$CHECK_TAG" "$@" 2>&1
}

out=$(run example-repo same-a same-b)
check "同じcommitを指すタグは0" "0" "$?"
check "同じcommitならOKと出す" "yes" "$(grep -q '^OK:' <<<"$out" && echo yes || echo no)"

out=$(run example-repo same-a later)
check "違うcommitは1" "1" "$?"
check "違うcommitならNGと出す" "yes" "$(grep -q '^NG:' <<<"$out" && echo yes || echo no)"

out=$(run example-repo same-a nosuchtag)
check "未知のタグは3" "3" "$?"

out=$(run nosuchrepo same-a same-b)
check "ghqに無いrepoは4" "4" "$?"

out=$(run example-repo same-a)
check "引数不足は2" "2" "$?"

# 呼び出し元の cwd を汚さない
before=$(pwd)
run example-repo same-a same-b >/dev/null
check "呼び出し元のcwdを変えない" "$before" "$(pwd)"

echo
echo "結果: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
