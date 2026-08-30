#!/bin/bash
# Markdown整形検査が、通常時は作業ツリー、--staged時はindexだけを見ることを検査する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/repository/markdown-format.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT
REPO="$TEST_DIR/repo"
BIN="$TEST_DIR/bin"
mkdir -p "$REPO" "$BIN"

cat >"$BIN/prettier" <<'STUB'
#!/bin/bash
stdin=0
check=0
for arg in "$@"; do
  case "$arg" in
    --stdin-filepath) stdin=1 ;;
    --check) check=1 ;;
  esac
done
if [ "$stdin" -eq 1 ]; then
  sed 's/BAD_FORMAT/GOOD_FORMAT/g'
  exit 0
fi
if [ "$check" -eq 1 ]; then
  for arg in "$@"; do
    [[ "$arg" == *.md ]] || continue
    grep -q BAD_FORMAT "$arg" && exit 1
  done
fi
exit 0
STUB
chmod +x "$BIN/prettier"

git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
printf '{"proseWrap":"preserve"}\n' >"$REPO/.prettierrc.json"

PASS=0
FAIL=0
TOTAL=0

check() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  ok   $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name: expected=$expected actual=$actual"
  fi
}

run_check() {
  env PATH="$BIN:$PATH" MARKDOWN_FORMAT_REPO_ROOT="$REPO" bash "$TARGET" "$@" >/dev/null 2>&1
}

printf '# GOOD_FORMAT\n' >"$REPO/doc.md"
git -C "$REPO" add .
git -C "$REPO" commit -qm initial

printf '# BAD_FORMAT\n' >"$REPO/doc.md"
run_check
check "通常検査は作業ツリーを見る" "1" "$?"

git -C "$REPO" add doc.md
printf '# GOOD_FORMAT\n' >"$REPO/doc.md"
run_check --staged
check "stage済み内容が未整形なら作業ツリーが整形済みでも失敗する" "1" "$?"

git -C "$REPO" restore --staged doc.md
git -C "$REPO" restore doc.md
printf '# ANOTHER_GOOD_FORMAT\n' >"$REPO/doc.md"
git -C "$REPO" add doc.md
printf '# BAD_FORMAT\n' >"$REPO/doc.md"
run_check --staged
check "stage済み内容が整形済みなら未stageの編集は無視する" "0" "$?"

mkdir -p "$REPO/.config/agents/skills-vendor/demo"
printf '# BAD_FORMAT\n' >"$REPO/.config/agents/skills-vendor/demo/SKILL.md"
git -C "$REPO" add "$REPO/.config/agents/skills-vendor/demo/SKILL.md"
run_check --staged
check "vendored skillはstage済みでも除外する" "0" "$?"

mkdir -p "$REPO/plugins/demo"
printf '# BAD_FORMAT\n' >"$REPO/plugins/demo/README.md"
git -C "$REPO" add "$REPO/plugins/demo/README.md"
run_check --staged
check "vendored pluginはstage済みでも除外する" "0" "$?"

ln -s doc.md "$REPO/link.md"
git -C "$REPO" add link.md
run_check --staged
check "Markdownへのsymlinkはstage済みでも除外する" "0" "$?"

echo
echo "結果: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
