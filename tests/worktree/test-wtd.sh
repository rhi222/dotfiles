#!/bin/bash
# wtdはdirtyやlockedなworktreeを通常のforceでは削除せず、二重forceだけで踏み越える。
# 一時repositoryとstub selectorを使い、現在のworktreeは変更しない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FUNC_DIR="$(cd "$REPO_ROOT/.config/fish/my/functions" && pwd)"
WTD="$FUNC_DIR/wtd.fish"
LOCK_REASON="$FUNC_DIR/__wt_lock_reason.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi
for f in "$WTD" "$LOCK_REASON"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f が存在しません"
    exit 1
  fi
done

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
REPO=""
WT=""
SLEEP_PID=""

setup() {
  TEST_DIR=$(mktemp -d)
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email "test@example.com"
  git -C "$REPO" config user.name "test"
  git -C "$REPO" commit -q --allow-empty -m init
  WT="$TEST_DIR/wt1"
  git -C "$REPO" worktree add -q "$WT" -b feat-x
}

teardown() {
  [[ -n "$SLEEP_PID" ]] && kill "$SLEEP_PID" 2>/dev/null
  SLEEP_PID=""
  rm -rf "$TEST_DIR"
}

# worktreeを未コミット変更ありにする
make_dirty() {
  echo dirty >"$WT/file.txt"
  git -C "$WT" add file.txt
}

# __wt_select をスタブして wtd を実行する。
# スタブは `  [.wt] <branch> <path> <sha>` 形式（awkが3列目をpathとして拾う）
run_wtd() {
  fish -c "
    function __wt_select; echo '  [.wt] feat-x $WT abc1234'; end
    source '$LOCK_REASON'
    source '$WTD'
    cd '$REPO'
    wtd $*
  " 2>&1
}

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

assert_dir_missing() {
  local path="$1" test_name="$2"
  TOTAL=$((TOTAL + 1))
  if [[ ! -d "$path" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name ($path が残っている)"
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
    echo "  FAIL: $test_name ($path が消えている)"
  fi
}

echo "=== wtd テスト ==="
echo ""

# --- 1. clean なworktreeは force なしで削除できる（回帰） ---
echo "[1] 通常削除"
setup
output=$(run_wtd)
assert_dir_missing "$WT" "worktreeが削除される"
assert_contains "削除:" "$output" "削除メッセージを出す"
teardown
echo ""

# --- 2. dirty は force なしで失敗、-f で成功（回帰） ---
echo "[2] dirty worktree"
setup
make_dirty
output=$(run_wtd)
assert_dir_exists "$WT" "forceなしでは削除されない"
assert_contains "--force" "$output" "gitのエラーを表示する"

output=$(run_wtd -f)
assert_dir_missing "$WT" "-f で削除される"
teardown
echo ""

# --- 3. lock + 死んだpid → 終了済みセッションだとヒントを出す ---
echo "[3] lock（死んだpid）"
setup
# 確実に存在しないpidを使う（sleepを起動して即killしpidを再利用させない）
sleep 60 &
dead_pid=$!
kill "$dead_pid" 2>/dev/null
wait "$dead_pid" 2>/dev/null
git -C "$REPO" worktree lock --reason "claude session feat-x (pid $dead_pid start 1520207)" "$WT"
output=$(run_wtd -f)
assert_dir_exists "$WT" "-f だけでは削除しない"
assert_contains "終了済み" "$output" "終了済みセッションだと伝える"
assert_contains "wtd -ff" "$output" "-ff を案内する"
teardown
echo ""

# --- 4. lock + 生きているpid → 実行中だと警告する ---
echo "[4] lock（生きているpid）"
setup
sleep 60 &
SLEEP_PID=$!
git -C "$REPO" worktree lock --reason "claude session feat-x (pid $SLEEP_PID start 1520207)" "$WT"
output=$(run_wtd -f)
assert_dir_exists "$WT" "-f だけでは削除しない"
assert_contains "実行中" "$output" "実行中だと警告する"
assert_contains "$SLEEP_PID" "$output" "pidを表示する"
teardown
echo ""

# --- 5. lock理由にpidが無い場合は汎用ヒント ---
echo "[5] lock（pidなし）"
setup
git -C "$REPO" worktree lock --reason "manual hold" "$WT"
output=$(run_wtd -f)
assert_dir_exists "$WT" "-f だけでは削除しない"
assert_contains "manual hold" "$output" "lock理由を表示する"
assert_contains "wtd -ff" "$output" "-ff を案内する"
teardown
echo ""

# --- 6. -ff は lock を踏み越えて削除する ---
echo "[6] -ff"
setup
sleep 60 &
SLEEP_PID=$!
git -C "$REPO" worktree lock --reason "claude session feat-x (pid $SLEEP_PID start 1520207)" "$WT"
output=$(run_wtd -ff)
assert_dir_missing "$WT" "-ff で削除される"
teardown
echo ""

# --- 7. --help は使い方を出して何もしない ---
echo "[7] --help"
setup
output=$(run_wtd --help)
assert_contains "使い方" "$output" "使い方を表示する"
assert_dir_exists "$WT" "worktreeは削除されない"
teardown
echo ""

# --- 8. __wt_lock_reason: 非lockのworktreeは空を返す ---
echo "[8] __wt_lock_reason"
setup
output=$(fish -c "source '$LOCK_REASON'; cd '$REPO'; __wt_lock_reason '$WT'; echo \"rc=\$status\"" 2>&1)
assert_contains "rc=1" "$output" "非lockはreturn 1"

git -C "$REPO" worktree lock --reason "hold me" "$WT"
output=$(fish -c "source '$LOCK_REASON'; cd '$REPO'; __wt_lock_reason '$WT'" 2>&1)
assert_eq "hold me" "$output" "lock理由を返す"
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
