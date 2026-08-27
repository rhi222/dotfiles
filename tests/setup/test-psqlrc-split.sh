#!/bin/bash
# psqlrc の「骨組みは repo / 案件固有は repo 外」という分離が崩れていないかを検証する。
#
# 実際の環境判定の挙動（is_prod / is_stg）は psql と稼働中のサーバが要るためここでは見ない。
# ここで守るのは構造の不変条件だけ。
#   1. repo 側の psqlrc に案件固有値が戻っていない
#   2. psqlrc が psqlrc.local を任意読み込みしている（無い端末で落ちない形）
#   3. 雛形が存在し、bootstrapが実体を用意する経路を持つ
#   4. 実体が gitignore されていて、追跡ファイルに混ざらない
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PSQLRC="$REPO_DIR/.config/psql/psqlrc"
EXAMPLE="$REPO_DIR/.config/psql/psqlrc.local.example"
BOOTSTRAP="$REPO_DIR/scripts/setup/bootstrap.sh"
BOOTSTRAP_IMPL="$REPO_DIR/internal/bootstrap/setup.sh"
LINK_IMPL="$REPO_DIR/internal/link/reconcile.sh"

PASS=0
FAIL=0
TOTAL=0

ok() {
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

ng() {
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

assert_grep() {
  local pattern="$1" file="$2" name="$3"
  if grep -qE -- "$pattern" "$file"; then ok "$name"; else ng "$name"; fi
}

assert_no_grep() {
  local pattern="$1" file="$2" name="$3"
  if grep -qE -- "$pattern" "$file"; then ng "$name"; else ok "$name"; fi
}

for f in "$PSQLRC" "$EXAMPLE" "$BOOTSTRAP" "$BOOTSTRAP_IMPL" "$LINK_IMPL"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: $f が存在しません"
    exit 1
  fi
done

echo "=== repo 側 psqlrc に案件固有値が無い ==="
# 案件固有値の形。DB名・DBユーザー名は「英小文字の連なり」を含む文字列比較や
# 5桁のポート番号として現れる。汎用の命名規約（*_prod など）だけを許す。
assert_no_grep "current_database\(\) ~ '\\.?[a-z]" "$PSQLRC" \
  "current_database() の比較先に実DB名が無い（汎用パターンのみ）"
assert_no_grep 'usename' "$PSQLRC" "DBユーザー名（usename）を参照していない"
assert_no_grep ":PORT" "$PSQLRC" "ポート番号による判定を持っていない"
echo ""

echo "=== psqlrc.local を任意読み込みしている ==="
assert_grep 'psqlrc\.local' "$PSQLRC" "psqlrc.local を参照している"
assert_grep 'test -f' "$PSQLRC" "存在チェックしてから読んでいる"
assert_grep '/dev/null' "$PSQLRC" "無い端末では /dev/null にフォールバックする"
assert_grep '^\\i :LOCALRC' "$PSQLRC" "解決したパスを \\i で読み込んでいる"
echo ""

echo "=== 既定値があり、local が無くても \\if が落ちない ==="
assert_grep '^\\set is_prod_local ' "$PSQLRC" "is_prod_local の既定値がある"
assert_grep '^\\set is_stg_local ' "$PSQLRC" "is_stg_local の既定値がある"
# \gset は真偽値を t / f で入れる。素の :var では SQL に埋められない
assert_grep ":'is_prod_local'::boolean" "$PSQLRC" "is_prod_local を引用付きでキャストしている"
assert_grep ":'is_stg_local'::boolean" "$PSQLRC" "is_stg_local を引用付きでキャストしている"
assert_grep 'COALESCE' "$PSQLRC" "NULL を false に畳んでいる"
echo ""

echo "=== 雛形と配布経路 ==="
assert_grep 'is_prod_local' "$EXAMPLE" "雛形が is_prod_local を設定している"
assert_grep 'is_stg_local' "$EXAMPLE" "雛形が is_stg_local を設定している"
assert_grep 'psqlrc\.local\.example\|\$HOME/\.config/psql/psqlrc\.local' "$BOOTSTRAP_IMPL" \
  "bootstrapが雛形から実体を作る"
assert_grep '[~]/\.config/psql' "$LINK_IMPL" "link reconcileが ~/.config/psql を用意する"
echo ""

echo "=== 実体が追跡されない ==="
TOTAL=$((TOTAL + 1))
if git -C "$REPO_DIR" check-ignore -q .config/psql/psqlrc.local; then
  PASS=$((PASS + 1))
  echo "  PASS: .config/psql/psqlrc.local は gitignore されている"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: .config/psql/psqlrc.local が gitignore されていない"
fi

TOTAL=$((TOTAL + 1))
if git -C "$REPO_DIR" ls-files --error-unmatch .config/psql/psqlrc.local >/dev/null 2>&1; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: .config/psql/psqlrc.local が追跡されている"
else
  PASS=$((PASS + 1))
  echo "  PASS: .config/psql/psqlrc.local は追跡されていない"
fi
echo ""

echo "=== 結果 ==="
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "テスト失敗"
  exit 1
fi
echo "全テスト成功"
exit 0
