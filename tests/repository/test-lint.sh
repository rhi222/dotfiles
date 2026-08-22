#!/bin/bash
# lint.sh のユニットテスト
#
# 検査対象の集め方（git ls-files ベース、skills-vendor/ 除外）と、
# Markdown / Fish の不正を各検査が落とすことを見る。
#
# 本物のリポジトリでは走らせない。LINT_REPO_ROOT で使い捨ての git リポジトリを
# 指し、shellcheck / shfmt / rumdl は PATH 前方の stub に差し替える（fish だけは実物を使う。
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
for arg in "$@"; do
  [[ "$arg" == *.sh ]] || continue
  [[ -f "$arg" ]] || exit 9
done
exit 0
STUB
    chmod +x "$STUB_DIR/$tool"
  done

  cat >"$STUB_DIR/rumdl" <<'STUB'
#!/bin/bash
[[ "${1:-}" == "check" ]] || exit 8
for arg in "$@"; do
  [[ "$arg" == *.md ]] || continue
  [[ -f "$arg" ]] || exit 9
  grep -q 'BAD_MARKDOWN' "$arg" && exit 1
done
exit 0
STUB
  chmod +x "$STUB_DIR/rumdl"

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

echo "== Markdown lint =="

setup
mkdir -p "$REPO/scripts"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
printf '# Good\n' >"$REPO/good.md"
git -C "$REPO" add -A
out=$(run_lint)
check "正しいMarkdownなら成功する" "0" "$?"
check "rumdlの検査を行ったと出力する" "yes" \
  "$(printf '%s' "$out" | grep -q '=== rumdl ===' && echo yes || echo no)"
teardown

setup
mkdir -p "$REPO/scripts"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
printf '# BAD_MARKDOWN\n' >"$REPO/broken.md"
git -C "$REPO" add -A
out=$(run_lint)
check "不正なMarkdownがあれば失敗する" "1" "$?"
teardown

setup
mkdir -p "$REPO/scripts" "$REPO/.config/claude/skills-vendor/x"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
printf '# BAD_MARKDOWN\n' >"$REPO/.config/claude/skills-vendor/x/vendored.md"
git -C "$REPO" add -A
out=$(run_lint)
check "skills-vendor配下のMarkdownは検査しない" "0" "$?"
teardown

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

setup
mkdir -p "$REPO/scripts"
echo '#!/bin/bash' >"$REPO/scripts/alive.sh"
echo '#!/bin/bash' >"$REPO/scripts/moved.sh"
git -C "$REPO" add -A
rm "$REPO/scripts/moved.sh"
out=$(run_lint)
# 未stageの移動では旧pathがindexに残る。実在確認なしでshellcheckへ渡すと、
# リファクタリング中だけlintが実行不能になる。
check "indexにだけ残る削除済みpathは検査しない" "0" "$?"
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

echo "== YAML の検査 =="
# **パーサ不在を名指しする。** lint.sh はパーサが無いと YAML を skip して通すので、
# 無いまま走らせると検知側の2件が理由不明で FAIL する（CI で踏んだ）。
# **判定は lint.sh 自身に任せる。** どの python を使うかの解決を二重に持つと、
# 片方だけ直したときに食い違う。
setup
mkdir -p "$REPO/scripts"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
printf 'a: 1\n' >"$REPO/probe.yml"
git -C "$REPO" add -A
if run_lint | grep -q "PyYAML を持つ python が無いため skip"; then
  teardown
  echo "ERROR: PyYAML が無いので YAML 検査を検査できません"
  echo "  入れる: sudo apt install python3-yaml（apt-packages.txt に宣言済み）"
  exit 1
fi
teardown

# **shfmt を .yml に誤って掛けた事故の再発防止。** shfmt は YAML を shell として
# パースしてインデントを潰すが exit 0 で返るため、検査が無いと壊れた workflow を
# push するまで気付けない（実際に踏んだ）。

setup
mkdir -p "$REPO/scripts" "$REPO/.github/workflows"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
printf 'name: x\njobs:\n  a:\n    runs-on: ubuntu-latest\n' >"$REPO/.github/workflows/ok.yml"
git -C "$REPO" add -A
out=$(run_lint)
check "正しい .yml なら成功する" "0" "$?"
check "yaml の検査を行ったと出力する" "yes" \
  "$(printf '%s' "$out" | grep -q '=== yaml ===' && echo yes || echo no)"
teardown

setup
mkdir -p "$REPO/scripts" "$REPO/.github/workflows"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
# インデントが揃っていない = shfmt に潰されたときと同型の壊れ方
printf 'a:\n  b: 1\n c: 2\n' >"$REPO/.github/workflows/broken.yml"
git -C "$REPO" add -A
out=$(run_lint)
check "パースできない .yml があれば失敗する" "1" "$?"
check "落ちたファイル名を出す" "yes" \
  "$(printf '%s' "$out" | grep -q 'broken.yml' && echo yes || echo no)"
teardown

setup
mkdir -p "$REPO/scripts" "$REPO/.github/workflows" "$REPO/.config/claude/skills-vendor/x"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
printf 'a:\n  b: 1\n c: 2\n' >"$REPO/.config/claude/skills-vendor/x/broken.yml"
git -C "$REPO" add -A
out=$(run_lint)
# .sh / .fish と同じ理由。vendored は追跡しているが自分は保守しない
check "skills-vendor 配下の .yml は検査しない" "0" "$?"
teardown

setup
mkdir -p "$REPO/scripts"
echo '#!/bin/bash' >"$REPO/scripts/a.sh"
git -C "$REPO" add -A
out=$(run_lint)
# **0件でもリポジトリルート自体を対象にしない。** xargs は入力が空でも
# コマンドを1回実行するので、-r を落とすと "$REPO_ROOT/" がパース対象になり
# ディレクトリを開こうとして全 fixture が落ちる（実際に踏んだ）
check ".yml が無くても成功する" "0" "$?"
check "0件なら対象が無いと言う" "yes" \
  "$(printf '%s' "$out" | grep -q '検査対象の .yml が無い' && echo yes || echo no)"
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
