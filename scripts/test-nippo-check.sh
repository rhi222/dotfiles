#!/bin/bash
# nippo-check.sh のユニットテスト
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NIPPO_CHECK="$SCRIPT_DIR/nippo-check.sh"

if [[ ! -x "$NIPPO_CHECK" ]]; then
  echo "ERROR: $NIPPO_CHECK が存在しないか実行権限がありません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

# テスト用一時ディレクトリ
TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
  export NIPPO_DIR="$TEST_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
  unset NIPPO_DIR
  unset NIPPO_NOW
}

assert_exit() {
  local expected_exit="$1"
  local actual_exit="$2"
  local test_name="$3"
  local output="${4:-}"

  TOTAL=$((TOTAL + 1))
  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name (expected exit=$expected_exit, got exit=$actual_exit)"
    echo "    output: $output"
  fi
}

assert_output_contains() {
  local expected="$1"
  local actual="$2"
  local test_name="$3"

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

assert_output_empty() {
  local actual="$1"
  local test_name="$2"

  TOTAL=$((TOTAL + 1))
  if [[ -z "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected empty output, got: $actual"
  fi
}

run_check() {
  local context="${1:-stop}"
  local output
  local exit_code=0
  output=$("$NIPPO_CHECK" "$context" 2>&1) || exit_code=$?
  echo "$output|$exit_code"
}

parse_output() {
  echo "$1" | sed 's/|[0-9]*$//'
}

parse_exit() {
  echo "$1" | grep -o '[0-9]*$'
}

# =============================================================================
# テストケース
# =============================================================================

echo "=== nippo-check.sh テスト ==="
echo ""

# --- 1. 土日判定 ---
echo "[1] 土日判定"

setup
# 2026-03-07 は土曜日
export NIPPO_NOW="2026-03-07 10:00"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 0 "$exit_code" "土曜日はexit 0"
assert_output_empty "$output" "土曜日は出力なし"

# 2026-03-08 は日曜日
export NIPPO_NOW="2026-03-08 14:00"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 0 "$exit_code" "日曜日はexit 0"
assert_output_empty "$output" "日曜日は出力なし"
teardown

echo ""

# --- 2. 9時前ファイルなし ---
echo "[2] 9時前ファイルなし"

setup
export NIPPO_NOW="2026-03-09 08:30"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 0 "$exit_code" "9時前でファイルなしはexit 0"
assert_output_empty "$output" "9時前でファイルなしは出力なし"
teardown

echo ""

# --- 3. 9時以降ファイルなし ---
echo "[3] 9時以降ファイルなし"

setup
export NIPPO_NOW="2026-03-09 10:00"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 1 "$exit_code" "9時以降でファイルなしはexit 1"
assert_output_contains "📝" "$output" "📝メッセージを含む"
assert_output_contains "今日の日報がまだ作成されていません" "$output" "日報未作成メッセージ"
teardown

echo ""

# --- 4. 未終了タイマー ---
echo "[4] 未終了タイマー"

setup
export NIPPO_NOW="2026-03-09 14:00"
cat > "$TEST_DIR/nippo.2026-03-09.md" << 'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- [ ] レビュー対応
NIPPO
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 1 "$exit_code" "未終了タイマーはexit 1"
assert_output_contains "🟢" "$output" "🟢メッセージを含む"
assert_output_contains "API設計" "$output" "タスク名を含む"
assert_output_contains "未終了" "$output" "未終了メッセージ"
teardown

echo ""

# --- 4b. 終了済みタイマー ---
echo "[4b] 終了済みタイマー（正常ケース）"

setup
export NIPPO_NOW="2026-03-09 14:00"
cat > "$TEST_DIR/nippo.2026-03-09.md" << 'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:30 🔴 end: API設計
- [x] レビュー対応
NIPPO
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 0 "$exit_code" "終了済みタイマーはexit 0"
assert_output_empty "$output" "終了済みタイマーは出力なし"
teardown

echo ""

# --- 5. 陳腐化検知（90分以上更新なし + 未完了タスクあり） ---
echo "[5] 陳腐化検知"

setup
export NIPPO_NOW="2026-03-09 14:00"
cat > "$TEST_DIR/nippo.2026-03-09.md" << 'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [ ] レビュー対応
- [ ] ドキュメント更新
NIPPO
# ファイルのmtimeを120分前に設定
touch -t "202603091200.00" "$TEST_DIR/nippo.2026-03-09.md"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 1 "$exit_code" "陳腐化検知はexit 1"
assert_output_contains "⏰" "$output" "⏰メッセージを含む"
assert_output_contains "更新されていません" "$output" "更新なしメッセージ"
teardown

echo ""

# --- 5b. 90分以上だが未完了タスクなし ---
echo "[5b] 90分以上経過だが未完了タスクなし"

setup
export NIPPO_NOW="2026-03-09 14:00"
cat > "$TEST_DIR/nippo.2026-03-09.md" << 'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [x] レビュー対応
NIPPO
touch -t "202603091200.00" "$TEST_DIR/nippo.2026-03-09.md"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 0 "$exit_code" "未完了なしならexit 0"
assert_output_empty "$output" "未完了なしなら出力なし"
teardown

echo ""

# --- 6. Finalize忘れ ---
echo "[6] Finalize忘れ"

setup
export NIPPO_NOW="2026-03-09 18:30"
cat > "$TEST_DIR/nippo.2026-03-09.md" << 'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [x] レビュー対応
NIPPO
# mtimeをNIPPO_NOWの10分前に設定（陳腐化を回避）
touch -t "202603091820.00" "$TEST_DIR/nippo.2026-03-09.md"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 1 "$exit_code" "Finalize忘れはexit 1"
assert_output_contains "📊" "$output" "📊メッセージを含む"
assert_output_contains "finalize" "$output" "finalizeメッセージ"
teardown

echo ""

# --- 6b. Finalize済み ---
echo "[6b] Finalize済み"

setup
export NIPPO_NOW="2026-03-09 18:30"
cat > "$TEST_DIR/nippo.2026-03-09.md" << 'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [x] レビュー対応

## Finalize:
- 振り返り完了
NIPPO
# mtimeをNIPPO_NOWの10分前に設定
touch -t "202603091820.00" "$TEST_DIR/nippo.2026-03-09.md"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 0 "$exit_code" "Finalize済みはexit 0"
assert_output_empty "$output" "Finalize済みは出力なし"
teardown

echo ""

# --- 7. 未完了タスクのみ ---
echo "[7] 未完了タスクのみ"

setup
export NIPPO_NOW="2026-03-09 15:00"
cat > "$TEST_DIR/nippo.2026-03-09.md" << 'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [ ] レビュー対応
- [-] ドキュメント更新
- [ ] テスト追加
- [x] コードレビュー
NIPPO
# mtimeをNIPPO_NOWの10分前に設定（陳腐化を回避）
touch -t "202603091450.00" "$TEST_DIR/nippo.2026-03-09.md"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 1 "$exit_code" "未完了タスクありはexit 1"
assert_output_contains "📋" "$output" "📋メッセージを含む"
assert_output_contains "未完了タスク" "$output" "未完了タスクメッセージ"
assert_output_contains "3件" "$output" "未完了3件を含む"
teardown

echo ""

# --- 8. 問題なし ---
echo "[8] 問題なし（全クリア）"

setup
export NIPPO_NOW="2026-03-09 15:00"
cat > "$TEST_DIR/nippo.2026-03-09.md" << 'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [x] レビュー対応
- [x] ドキュメント更新
NIPPO
# mtimeをNIPPO_NOWの10分前に設定
touch -t "202603091450.00" "$TEST_DIR/nippo.2026-03-09.md"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 0 "$exit_code" "問題なしはexit 0"
assert_output_empty "$output" "問題なしは出力なし"
teardown

echo ""

# --- 9. 優先度テスト: 未終了タイマーが未完了タスクより先 ---
echo "[9] 優先度テスト: 未終了タイマーが未完了タスクより優先"

setup
export NIPPO_NOW="2026-03-09 14:00"
cat > "$TEST_DIR/nippo.2026-03-09.md" << 'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- [ ] レビュー対応
- [ ] テスト追加
NIPPO
# mtimeをNIPPO_NOWの10分前に設定
touch -t "202603091350.00" "$TEST_DIR/nippo.2026-03-09.md"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
assert_exit 1 "$exit_code" "未終了タイマー優先でexit 1"
assert_output_contains "🟢" "$output" "🟢（未終了タイマー）が出力される"
# 📋（未完了タスク）は出力されないはず
TOTAL=$((TOTAL + 1))
if echo "$output" | grep -qF "📋"; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: 📋は出力されないべき"
  echo "    output: $output"
else
  PASS=$((PASS + 1))
  echo "  PASS: 📋は出力されない（未終了タイマーが優先）"
fi
teardown

echo ""

# =============================================================================
# 結果サマリ
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
