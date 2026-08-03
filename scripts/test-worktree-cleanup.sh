#!/bin/bash
# worktree-cleanup.sh のユニットテスト
# 一時ディレクトリにfixtureリポジトリとworktreeを作って検証する
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLEANUP="$SCRIPT_DIR/worktree-cleanup.sh"

if [[ ! -f "$CLEANUP" ]]; then
  echo "ERROR: $CLEANUP が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
REPO=""

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

teardown() {
  [[ -n "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
  TEST_DIR=""
}

echo "=== worktree-cleanup.sh テスト ==="
echo ""

# --- 1. CLI表面 ---
echo "[1] CLI表面"
output=$(bash "$CLEANUP" --help 2>&1)
assert_output_contains "usage" "$output" "--help が使い方を表示する"

exit_code=0
output=$(bash "$CLEANUP" --bogus-option 2>&1) || exit_code=$?
assert_eq 1 "$exit_code" "不明オプションは exit 1"
assert_output_contains "Unknown option" "$output" "不明オプション名を報告する"

# sourceしてデフォルト値を確認する（mainは走らない）
# shellcheck source=worktree-cleanup.sh
source "$CLEANUP"
assert_eq 0 "$EXECUTE" "EXECUTE の既定は 0（dry-run）"
assert_eq 0 "$FORCE" "FORCE の既定は 0"
assert_eq 0 "$SHOW_SIZE" "SHOW_SIZE の既定は 0"

parse_args --execute --force --size
assert_eq 1 "$EXECUTE" "--execute で EXECUTE=1"
assert_eq 1 "$FORCE" "--force で FORCE=1"
assert_eq 1 "$SHOW_SIZE" "--size で SHOW_SIZE=1"

assert_eq "1.0G" "$(format_kb 1048576)" "format_kb: 1048576KB → 1.0G"
assert_eq "500M" "$(format_kb 512000)" "format_kb: 512000KB → 500M"
assert_eq "12K" "$(format_kb 12)" "format_kb: 12KB → 12K"

# 存在しないパスは必ず 0 を返す（呼び出し側が $(( )) で加算するため）
assert_eq 0 "$(path_size_kb /nonexistent/path/xyz)" "path_size_kb: 存在しないパスは 0"
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
