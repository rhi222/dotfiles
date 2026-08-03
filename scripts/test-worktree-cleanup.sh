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

# fixtureリポジトリを作る。worktreeは各テストで必要な分だけ生やす。
setup() {
  TEST_DIR=$(mktemp -d)
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email "test@example.com"
  git -C "$REPO" config user.name "test"
  echo "# fixture" >"$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -qm "init"
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

# --- 2. worktreeメタデータの抽出 ---
echo "[2] worktreeメタデータの抽出"
setup
git -C "$REPO" worktree add -q "$REPO/.wt/normal" -b normal
git -C "$REPO" worktree add -q "$REPO/.wt/lockme" -b lockme
git -C "$REPO" worktree lock --reason "claude session (pid 123)" "$REPO/.wt/lockme"
git -C "$REPO" worktree add -q --detach "$REPO/.wt/det"
git -C "$REPO" worktree add -q "$REPO/.wt/gone" -b gone
rm -rf "$REPO/.wt/gone"
# ディレクトリ名とブランチ名がずれるケース（実環境で発生している）
git -C "$REPO" worktree add -q "$REPO/.wt/dirname-differs" -b actual-branch-name

wt_out=$(list_worktrees "$REPO")

# フィールド区切りのタブは $'\t' で明示する（リテラルタブに依存しない）
TB=$'\t'
assert_output_lacks "${REPO}${TB}main${TB}" "$wt_out" "main worktree は含まれない"
assert_output_contains "$REPO/.wt/normal${TB}normal${TB}-${TB}" "$wt_out" "通常のworktree: flagsは -"
assert_output_contains "$REPO/.wt/lockme${TB}lockme${TB}locked${TB}claude session (pid 123)" "$wt_out" "locked: flagsとdetailを拾う"
assert_output_contains "$REPO/.wt/det${TB}${TB}-${TB}" "$wt_out" "detached: branchは空文字"
assert_output_contains "$REPO/.wt/gone${TB}gone${TB}prunable${TB}" "$wt_out" "prunable: flagsに prunable"
assert_output_contains "$REPO/.wt/dirname-differs${TB}actual-branch-name${TB}-${TB}" "$wt_out" "ブランチ名はディレクトリ名ではなくbranch行から取る"
assert_eq 5 "$(echo "$wt_out" | grep -c .)" "linked worktree は5件"
teardown
echo ""

# --- 3. リポジトリの走査 ---
echo "[3] リポジトリの走査"
setup
# 走査ルート配下に2つ目のリポジトリを作る
REPO2="$TEST_DIR/nested/repo2"
mkdir -p "$REPO2"
git -C "$REPO2" init -q -b main
git -C "$REPO2" config user.email "test@example.com"
git -C "$REPO2" config user.name "test"
echo "x" >"$REPO2/f"
git -C "$REPO2" add f
git -C "$REPO2" commit -qm "init"

repos_out=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" discover_repos)
assert_output_contains "$REPO" "$repos_out" "走査ルート直下のリポジトリを見つける"
assert_output_contains "$REPO2" "$repos_out" "ネストしたリポジトリも見つける"
assert_eq 2 "$(echo "$repos_out" | grep -c .)" "リポジトリは2件"
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
