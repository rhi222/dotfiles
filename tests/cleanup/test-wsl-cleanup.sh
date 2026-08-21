#!/bin/bash
# wsl-cleanup.sh のユニットテスト（characterization test）
#
# 破壊的な rm -rf を含むため、既存挙動を固定して回帰を検知する。
# 実ファイルシステムを汚さないよう、削除対象は必ず mktemp 配下に閉じる。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
CLEANUP="$SCRIPTS_DIR/wsl-cleanup.sh"

if [[ ! -f "$CLEANUP" ]]; then
  echo "ERROR: $CLEANUP が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""

assert_eq() {
  local expected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name (expected=$expected, got=$actual)"
  fi
}

assert_output_contains() {
  local expected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$actual" | grep -qF "$expected"; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected to contain: $expected"
    echo "    actual: $actual"
  fi
}

assert_output_lacks() {
  local unexpected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$actual" | grep -qF "$unexpected"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected NOT to contain: $unexpected"
    echo "    actual: $actual"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  fi
}

assert_dir_exists() {
  local path="$1" test_name="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -d "$path" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name ($path が存在しない)"
  fi
}

assert_dir_missing() {
  local path="$1" test_name="$2"
  TOTAL=$((TOTAL + 1))
  if [[ ! -d "$path" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name ($path が存在してしまっている)"
  fi
}

setup() {
  TEST_DIR=$(mktemp -d)
}

teardown() {
  [[ -n "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
  TEST_DIR=""
}

echo "=== wsl-cleanup.sh テスト ==="
echo ""

# --- 1. CLI表面（サブプロセス実行） ---
echo "[1] CLI表面"
output=$(bash "$CLEANUP" --help 2>&1)
exit_code=$?
assert_eq 0 "$exit_code" "--help は exit 0"
assert_output_contains "WSL2 開発環境のキャッシュ" "$output" "--help がスクリプト説明を表示する"
assert_output_contains "bash scripts/wsl-cleanup.sh --execute" "$output" "--help が使い方を表示する"

exit_code=0
output=$(bash "$CLEANUP" --bogus-option 2>&1) || exit_code=$?
assert_eq 1 "$exit_code" "不明オプションは exit 1"
assert_output_contains "Unknown option: --bogus-option" "$output" "不明オプション名を報告する"
assert_output_contains "Usage:" "$output" "使い方を stderr に出す"
echo ""

# --- source して関数を単体で叩く ---
# shellcheck source=wsl-cleanup.sh
source "$CLEANUP"
# 端末依存の色付けを潰し、出力アサートを決定的にする（スクリプト本体は変更しない）。
C_BOLD="" C_GREEN="" C_YELLOW="" C_CYAN="" C_RESET=""

# --- 2. 引数パースのデフォルトと副作用 ---
echo "[2] 引数パース"
assert_eq 0 "$EXECUTE" "EXECUTE の既定は 0（dry-run）"
parse_args --execute
assert_eq 1 "$EXECUTE" "--execute で EXECUTE=1"
EXECUTE=0
echo ""

# --- 3. path_size ---
echo "[3] path_size"
setup
mkdir -p "$TEST_DIR/some"
echo "data" >"$TEST_DIR/some/file"
size=$(path_size "$TEST_DIR/some")
TOTAL=$((TOTAL + 1))
if [[ -n "$size" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: 存在するパスは非空のサイズを返す ($size)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: 存在するパスは非空のサイズを返す (空だった)"
fi
assert_eq "" "$(path_size "$TEST_DIR/nonexistent")" "存在しないパスは空文字を返す"
teardown
echo ""

# --- 4. norm（パス正規化：現行 store を誤って消さないための要） ---
echo "[4] norm パス正規化"
setup
# 末尾スラッシュの有無で結果が変わらない
assert_eq "$(norm "$TEST_DIR/a/b")" "$(norm "$TEST_DIR/a/b/")" "末尾スラッシュの有無で同一に正規化する"
# .. を畳む
assert_eq "$(norm "$TEST_DIR/y")" "$(norm "$TEST_DIR/x/../y")" ".. を含む入力を畳んで同一にする"
# symlink を解決する（同じ実体を指すパスは同一と判定できる）
mkdir -p "$TEST_DIR/real/v3"
ln -s "$TEST_DIR/real" "$TEST_DIR/link"
assert_eq "$(norm "$TEST_DIR/real/v3")" "$(norm "$TEST_DIR/link/v3")" "symlink 経由でも同一実体は同一に正規化する"
# 正規化結果は入力のルート配下から外に出ない（$HOME 直下や / へ飛ばない）
normed=$(norm "$TEST_DIR/real/v3")
assert_output_contains "$(norm "$TEST_DIR")/real/v3" "$normed" "正規化はルート配下に留まり別ディレクトリへ飛ばない"
# 別ディレクトリは別の正規化結果になる（＝現行以外は削除対象に回る）
TOTAL=$((TOTAL + 1))
if [[ "$(norm "$TEST_DIR/real/v3")" != "$(norm "$TEST_DIR/real/v10")" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: 異なる store は異なる正規化結果になる"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: 異なる store は異なる正規化結果になる"
fi
teardown
echo ""

# --- 5. clean_path（破壊的削除の中核） ---
echo "[5] clean_path"
setup
# 5-1. 存在しないパスは skip して何も消さない
out=$(clean_path "missing label" "$TEST_DIR/nope")
assert_output_contains "[skip]" "$out" "存在しないパスは [skip]"
assert_output_contains "見つかりません" "$out" "存在しないパスは見つからない旨を出す"

# 5-2. dry-run（EXECUTE=0）は削除しない
EXECUTE=0
mkdir -p "$TEST_DIR/keepme"
: >"$TEST_DIR/keepme/sentinel"
out=$(clean_path "keepme" "$TEST_DIR/keepme")
assert_output_contains "(dry-run: 削除しません)" "$out" "dry-run は削除しない旨を出す"
assert_dir_exists "$TEST_DIR/keepme" "dry-run では対象を削除しない"

# 5-3. execute（EXECUTE=1）は削除する
EXECUTE=1
mkdir -p "$TEST_DIR/delme"
: >"$TEST_DIR/delme/sentinel"
out=$(clean_path "delme" "$TEST_DIR/delme")
assert_output_contains "削除しました" "$out" "execute は削除完了を報告する"
assert_dir_missing "$TEST_DIR/delme" "execute では対象を削除する"
EXECUTE=0
teardown
echo ""

# --- 6. clean_cmd ---
echo "[6] clean_cmd"
setup
# 6-1. コマンドが無ければ skip して実行しない
marker="$TEST_DIR/marker"
out=$(clean_cmd "missing" no_such_cmd_xyzzy "" -- no_such_cmd_xyzzy)
assert_output_contains "コマンドが無いためスキップ" "$out" "コマンドが無ければスキップ"

# 6-2. dry-run はコマンドを実行しない
EXECUTE=0
rm -f "$marker"
out=$(clean_cmd "touch-test" touch "" -- touch "$marker")
assert_output_contains "(dry-run: 実行しません)" "$out" "dry-run は実行しない旨を出す"
assert_dir_missing "$marker" "dry-run ではコマンドを実行しない（マーカー未作成）"

# 6-3. execute はコマンドを実行する
EXECUTE=1
rm -f "$marker"
out=$(clean_cmd "touch-test" touch "" -- touch "$marker")
assert_output_contains "実行しました" "$out" "execute は実行完了を報告する"
TOTAL=$((TOTAL + 1))
if [[ -f "$marker" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: execute ではコマンドを実行する（マーカー作成）"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: execute ではコマンドを実行する（マーカー未作成）"
fi
EXECUTE=0
teardown
echo ""

# =============================================================================
echo "=== 結果 ==="
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
echo ""
if [[ "$FAIL" -gt 0 ]]; then
  echo "テスト失敗"
  exit 1
else
  echo "全テスト成功"
  exit 0
fi
