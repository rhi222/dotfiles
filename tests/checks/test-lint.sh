#!/bin/bash
# lint.sh のユニットテスト
#
# 検査対象の集め方（git ls-files ベース、skills-vendor/ 除外）と、
# .fish の構文チェックが実際に落ちることを見る。
#
# 本物のリポジトリでは走らせない。LINT_REPO_ROOT で使い捨ての git リポジトリを
# 指し、shellcheck / shfmt は PATH 前方の stub に差し替える（fish だけは実物を使う。
# 構文エラーを本当に検出できるかがこのテストの主目的なので）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
TARGET="$SCRIPTS_DIR/lint.sh"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
STUB_DIR=""
REPO=""

setup() {
  TEST_DIR=$(mktemp -d)
  STUB_DIR="$TEST_DIR/bin"
  REPO="$TEST_DIR/repo"
  mkdir -p "$STUB_DIR" "$REPO"

  for tool in shellcheck shfmt; do
    cat >"$STUB_DIR/$tool" <<'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$STUB_DIR/$tool"
  done

  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name t
}

teardown() {
  [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

run_lint() {
  env PATH="$STUB_DIR:$PATH" LINT_REPO_ROOT="$REPO" bash "$TARGET" 2>&1
}

check() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
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

good_fish() { printf 'function ok\n    echo hi\nend\n'; }
# `if` を閉じないので fish -n が落ちる
bad_fish() { printf 'function broken\n    if true\nend\n'; }

echo "== .fish の構文チェック =="

setup
mkdir -p "$REPO/scripts"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
good_fish >"$REPO/good.fish"
git -C "$REPO" add -A
out=$(run_lint)
check "正しい .fish だけなら成功する" "0" "$?"
check "fish の検査を行ったと出力する" "yes" \
  "$(printf '%s' "$out" | grep -q 'fish -n' && echo yes || echo no)"
teardown

setup
mkdir -p "$REPO/scripts"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
bad_fish >"$REPO/broken.fish"
git -C "$REPO" add -A
out=$(run_lint)
check "構文エラーのある .fish があれば失敗する" "1" "$?"
check "落ちたファイル名を出す" "yes" \
  "$(printf '%s' "$out" | grep -q 'broken.fish' && echo yes || echo no)"
teardown

echo "== 対象の集め方 =="

setup
mkdir -p "$REPO/scripts" "$REPO/.config/claude/skills-vendor/x"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
bad_fish >"$REPO/.config/claude/skills-vendor/x/vendored.fish"
git -C "$REPO" add -A
out=$(run_lint)
# vendored は追跡しているが自分は保守しない。.sh と同じ理由で .fish も除外する
check "skills-vendor 配下の .fish は検査しない" "0" "$?"
teardown

setup
mkdir -p "$REPO/scripts"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
git -C "$REPO" add -A
bad_fish >"$REPO/untracked.fish"
out=$(run_lint)
# --others を含めるのは、書いたばかりのファイルが commit するまで検査されず
# CI で初めて落ちるのを避けるため（.sh と同じ理由）
check "未追跡の .fish も検査する" "1" "$?"
teardown

setup
mkdir -p "$REPO/scripts"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
git -C "$REPO" add -A
bad_fish >"$REPO/ignored.fish"
echo 'ignored.fish' >"$REPO/.gitignore"
git -C "$REPO" add .gitignore
out=$(run_lint)
# ignore 済み＝自分が保守しない
check "gitignore された .fish は検査しない" "0" "$?"
teardown

echo "== .fish が1本も無いとき =="

setup
mkdir -p "$REPO/scripts"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
git -C "$REPO" add -A
out=$(run_lint)
# .sh が対象0本ならエラーだが、.fish は0本でも正常（fish を使わない構成もありうる）
check ".fish が無くても成功する" "0" "$?"
teardown

echo "== fish 未導入の端末 =="

setup
mkdir -p "$REPO/scripts"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
bad_fish >"$REPO/broken.fish"
git -C "$REPO" add -A
# fish だけが引けない PATH を組む。/usr/bin をまるごと外すと git も xargs も
# 消えて lint 自体が動かないので、必要なものだけを symlink で並べた箱を作る。
NOFISH="$TEST_DIR/nofish"
mkdir -p "$NOFISH"
# printf は bash の組み込みでもあるので type -P で外部コマンドの実体を引く
# （command -v だと "printf" が返り、自分を指す symlink ができて無限ループになる）
for t in git xargs sort dirname printf; do
  ln -sf "$(type -P "$t")" "$NOFISH/$t"
done
ln -sf "$STUB_DIR/shellcheck" "$NOFISH/shellcheck"
ln -sf "$STUB_DIR/shfmt" "$NOFISH/shfmt"
out=$(env PATH="$NOFISH" LINT_REPO_ROOT="$REPO" /bin/bash "$TARGET" 2>&1)
rc=$?
# fish が無いだけで lint 全体を落とすと、fish を使わない端末で commit できなくなる
check "fish が無ければスキップして成功する" "0" "$rc"
check "スキップした理由を出す" "yes" \
  "$(printf '%s' "$out" | grep -q -i 'skip' && echo yes || echo no)"
teardown

echo
echo "結果: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
