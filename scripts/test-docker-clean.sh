#!/bin/bash
# fish関数 dclean / __docker_clean_* のユニットテスト
# docker をフェイクスクリプトに差し替え、固定のフィクスチャを返させて検証する
#
# fishのコードをシングルクォートで埋め込むため、$status や $argv をbashに展開させない。
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FUNC_DIR="$(cd "$SCRIPT_DIR/../.config/fish/my/functions" && pwd)"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq が見つかりません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

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

assert_contains() {
  local expected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  # -e: `--force` のようにハイフン始まりの文字列を検索できるようにする
  if echo "$actual" | grep -qF -e "$expected"; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected to contain: $expected"
    echo "    actual: $actual"
  fi
}

# 純関数だけを source して式を評価する（docker 不要）
run_pure() {
  fish -c "
    source '$FUNC_DIR/__docker_clean_size_to_bytes.fish'
    source '$FUNC_DIR/__docker_clean_format_bytes.fish'
    $1
  " 2>&1
}

echo "=== docker-clean テスト ==="
echo ""

# --- 1. サイズ文字列 → バイト数 ---
echo "[1] __docker_clean_size_to_bytes"
assert_eq "0" "$(run_pure '__docker_clean_size_to_bytes 0B')" "0B"
assert_eq "4128" "$(run_pure '__docker_clean_size_to_bytes 4.128kB')" "小数付き kB"
assert_eq "577800000" "$(run_pure '__docker_clean_size_to_bytes "577.8MB*"')" "共有マーク付き MB"
assert_eq "12530000000" "$(run_pure '__docker_clean_size_to_bytes "12.53GB (51%)"')" "パーセント注記付き GB"
assert_eq "1200000000000" "$(run_pure '__docker_clean_size_to_bytes 1.2TB')" "TB"
assert_eq "1024" "$(run_pure '__docker_clean_size_to_bytes 1KiB')" "二進単位 KiB"
assert_eq "19306776000" "$(run_pure '__docker_clean_size_to_bytes 12.53GB 6.776GB 776000B')" "複数引数を合算する"
assert_eq "0" "$(run_pure '__docker_clean_size_to_bytes')" "引数なしは0"
assert_contains "解釈できない" "$(run_pure '__docker_clean_size_to_bytes nonsense')" "不正な入力はエラーを出す"
assert_eq "1" "$(run_pure '__docker_clean_size_to_bytes nonsense >/dev/null 2>&1; echo $status')" "不正な入力は非ゼロ終了"
echo ""

# --- 2. バイト数 → 人間可読 ---
echo "[2] __docker_clean_format_bytes"
assert_eq "0B" "$(run_pure '__docker_clean_format_bytes 0')" "0"
assert_eq "0B" "$(run_pure '__docker_clean_format_bytes')" "引数なしは0B"
assert_eq "512B" "$(run_pure '__docker_clean_format_bytes 512')" "B"
assert_eq "50.3MB" "$(run_pure '__docker_clean_format_bytes 50280000')" "MB"
assert_eq "19.3GB" "$(run_pure '__docker_clean_format_bytes 19300000000')" "GB"
assert_eq "1.2TB" "$(run_pure '__docker_clean_format_bytes 1200000000000')" "TB"
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
