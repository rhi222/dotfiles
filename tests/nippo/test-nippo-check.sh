#!/bin/bash
# 日報checkは時刻・曜日・日報状態ごとに通知の有無と契約コードを一意に返し、
# stopでは低優先度チェックを実行しない。
# 被テストコマンドの失敗 rc は run_check 内で `|| exit_code=$?` により捕捉するため -e と両立する
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
NIPPO_CHECK="$SCRIPTS_DIR/nippo/check.sh"

if [[ ! -x "$NIPPO_CHECK" ]]; then
  echo "ERROR: $NIPPO_CHECK が存在しないか実行権限がありません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

# フィクスチャの置き場は nippo-paths.sh に解決させる。
# ここでレイアウトを直書きすると、ディレクトリ構造を変えるたびに
# テストが本体と食い違って落ちる（実際にフラット→年/月の移行で踏んだ）。
# shellcheck source=lib/nippo-paths.sh
source "$SCRIPTS_DIR/lib/nippo-paths.sh"

# 全ケースが同じ日付のフィクスチャを使う
FIXTURE_DATE="2026-03-09"

# テスト用一時ディレクトリ
TEST_DIR=""
# 日報フィクスチャの絶対パス。setup() で毎回決め直す
FIXTURE=""

setup() {
  TEST_DIR=$(mktemp -d)
  export NIPPO_DIR="$TEST_DIR"
  FIXTURE="$(nippo_daily_file "$FIXTURE_DATE")"
  mkdir -p "$(nippo_daily_dir "$FIXTURE_DATE")"
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

assert_output_nonempty() {
  local actual="$1"
  local test_name="$2"

  TOTAL=$((TOTAL + 1))
  if [[ -n "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected non-empty output, got empty"
  fi
}

assert_output_not_contains() {
  local unexpected="$1"
  local actual="$2"
  local test_name="$3"

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

# stderr は契約行（機械可読）、stdout は通知本文（人間向け）。
# 消費者は 2>/dev/null で stderr を捨てて stdout だけを通知に使うので、
# テストも両者を分けて取り、通知本文の判定は stdout だけを見る。
# 保存先は setup() が張る $TEST_DIR。run_check はコマンド置換のサブシェルで
# 走るため、置き場をローカルに持たせると親へ伝わらない。親スコープの
# $TEST_DIR を直に使い、書き込みも読み出しも同じパスへ向ける。
contract_file() {
  echo "$TEST_DIR/stderr.log"
}
run_check() {
  local context="${1:-stop}"
  local output
  local exit_code=0
  output=$("$NIPPO_CHECK" "$context" 2>"$(contract_file)") || exit_code=$?
  echo "$output|$exit_code"
}

parse_output() {
  echo "${1%|*}"
}

parse_exit() {
  echo "$1" | grep -o '[0-9]*$'
}

# 直前の run_check が stderr へ出した契約行を読む。
parse_contract() {
  local f
  f="$(contract_file)"
  [[ -f "$f" ]] && cat "$f" || true
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
contract=$(parse_contract)
assert_exit 0 "$exit_code" "土曜日はexit 0"
assert_output_empty "$output" "土曜日は出力なし"
assert_output_contains "HITS=none" "$contract" "土曜日は none を報告"

# 2026-03-08 は日曜日
export NIPPO_NOW="2026-03-08 14:00"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 0 "$exit_code" "日曜日はexit 0"
assert_output_empty "$output" "日曜日は出力なし"
assert_output_contains "HITS=none" "$contract" "日曜日は none を報告"
teardown

echo ""

# --- 2. 9時前ファイルなし ---
echo "[2] 9時前ファイルなし"

setup
export NIPPO_NOW="2026-03-09 08:30"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 0 "$exit_code" "9時前でファイルなしはexit 0"
assert_output_empty "$output" "9時前でファイルなしは出力なし"
assert_output_contains "HITS=none" "$contract" "9時前は none を報告"
teardown

echo ""

# --- 3. 9時以降ファイルなし ---
echo "[3] 9時以降ファイルなし"

setup
export NIPPO_NOW="2026-03-09 10:00"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 1 "$exit_code" "9時以降でファイルなしはexit 1"
assert_output_nonempty "$output" "通知本文を出す"
assert_output_contains "nippo-check: CONTEXT=stop HITS=missing" "$contract" "missing を報告する"
teardown

echo ""

# --- 4. 未終了タイマー ---
echo "[4] 未終了タイマー"

setup
export NIPPO_NOW="2026-03-09 14:00"
cat >"$FIXTURE" <<'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- [ ] レビュー対応
NIPPO
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 1 "$exit_code" "未終了タイマーはexit 1"
assert_output_nonempty "$output" "通知本文を出す"
assert_output_contains "HITS=open-timer" "$contract" "open-timer を報告する"
teardown

echo ""

# --- 4b. 終了済みタイマー ---
echo "[4b] 終了済みタイマー（正常ケース）"

setup
export NIPPO_NOW="2026-03-09 14:00"
cat >"$FIXTURE" <<'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:30 🔴 end: API設計
- [x] レビュー対応
NIPPO
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 0 "$exit_code" "終了済みタイマーはexit 0"
assert_output_empty "$output" "終了済みタイマーは出力なし"
assert_output_contains "HITS=none" "$contract" "問題なしは none を報告"
teardown

echo ""

# --- 5. 陳腐化検知（90分以上更新なし + 未完了タスクあり） ---
echo "[5] 陳腐化検知（cronのみ）"

setup
export NIPPO_NOW="2026-03-09 14:00"
cat >"$FIXTURE" <<'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [ ] レビュー対応
- [ ] ドキュメント更新
NIPPO
# ファイルのmtimeを120分前に設定
touch -t "202603091200.00" "$FIXTURE"
result=$(run_check cron)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 1 "$exit_code" "cronでは陳腐化検知でexit 1"
assert_output_nonempty "$output" "通知本文を出す"
assert_output_contains "HITS=stale" "$contract" "stale を報告する"

# 同じ状態でも stop では通知しない（低優先度チェックのため）
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 0 "$exit_code" "stopでは陳腐化検知はexit 0"
assert_output_empty "$output" "stopでは陳腐化検知は出力なし"
assert_output_not_contains "stale" "$contract" "stopでは stale を報告しない"
teardown

echo ""

# --- 5b. 90分以上だが未完了タスクなし ---
# 件数ロジックの下限側。cron（全チェック）でも未完了0件なら陳腐化は発火しない。
# case 5（未完了ありで発火）と同じ経過時間・同じ cron で件数だけを変えた対。
echo "[5b] 90分以上経過だが未完了タスクなし"

setup
export NIPPO_NOW="2026-03-09 14:00"
cat >"$FIXTURE" <<'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [x] レビュー対応
NIPPO
touch -t "202603091200.00" "$FIXTURE"
result=$(run_check cron)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 0 "$exit_code" "未完了なしならexit 0"
assert_output_empty "$output" "未完了なしなら出力なし"
assert_output_not_contains "stale" "$contract" "未完了0件なら stale を報告しない"
teardown

echo ""

# --- 6. Finalize忘れ ---
echo "[6] Finalize忘れ"

setup
export NIPPO_NOW="2026-03-09 18:30"
cat >"$FIXTURE" <<'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [x] レビュー対応
NIPPO
# mtimeをNIPPO_NOWの10分前に設定（陳腐化を回避）
touch -t "202603091820.00" "$FIXTURE"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 1 "$exit_code" "Finalize忘れはexit 1"
assert_output_nonempty "$output" "通知本文を出す"
assert_output_contains "HITS=finalize" "$contract" "finalize を報告する"
teardown

echo ""

# --- 6b. Finalize済み ---
echo "[6b] Finalize済み"

setup
export NIPPO_NOW="2026-03-09 18:30"
cat >"$FIXTURE" <<'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [x] レビュー対応

## Finalize:
- 振り返り完了
NIPPO
# mtimeをNIPPO_NOWの10分前に設定
touch -t "202603091820.00" "$FIXTURE"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 0 "$exit_code" "Finalize済みはexit 0"
assert_output_empty "$output" "Finalize済みは出力なし"
assert_output_not_contains "finalize" "$contract" "Finalize済みは finalize を報告しない"
teardown

echo ""

# --- 7. 未完了タスクのみ ---
echo "[7] 未完了タスクのみ（cronのみ）"

setup
export NIPPO_NOW="2026-03-09 15:00"
cat >"$FIXTURE" <<'NIPPO'
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
touch -t "202603091450.00" "$FIXTURE"
result=$(run_check cron)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 1 "$exit_code" "cronでは未完了タスクありでexit 1"
assert_output_nonempty "$output" "通知本文を出す"
assert_output_contains "HITS=incomplete" "$contract" "incomplete を報告する"

# 同じ状態でも stop では通知しない（一日中鳴り続けるため）
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 0 "$exit_code" "stopでは未完了タスクはexit 0"
assert_output_empty "$output" "stopでは未完了タスクは出力なし"
assert_output_not_contains "incomplete" "$contract" "stopでは incomplete を報告しない"
teardown

echo ""

# --- 8. 問題なし ---
echo "[8] 問題なし（全クリア）"

setup
export NIPPO_NOW="2026-03-09 15:00"
cat >"$FIXTURE" <<'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [x] レビュー対応
- [x] ドキュメント更新
NIPPO
# mtimeをNIPPO_NOWの10分前に設定
touch -t "202603091450.00" "$FIXTURE"
result=$(run_check stop)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 0 "$exit_code" "問題なしはexit 0"
assert_output_empty "$output" "問題なしは出力なし"
assert_output_contains "HITS=none" "$contract" "問題なしは none を報告"
teardown

echo ""

# --- 9. 優先度テスト: 未終了タイマーが未完了タスクより先 ---
# cron（全チェック）で走らせる。未終了タイマーと未完了タスクの両方が発火条件を
# 満たすが、先に評価される未終了タイマーが preempt し incomplete は報告されない。
# stop だと incomplete は無効化されて競合が起きず、優先順位を検証できない。
echo "[9] 優先度テスト: 未終了タイマーが未完了タスクより優先"

setup
export NIPPO_NOW="2026-03-09 14:00"
cat >"$FIXTURE" <<'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- [ ] レビュー対応
- [ ] テスト追加
NIPPO
# mtimeをNIPPO_NOWの10分前に設定
touch -t "202603091350.00" "$FIXTURE"
result=$(run_check cron)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 1 "$exit_code" "未終了タイマー優先でexit 1"
assert_output_contains "HITS=open-timer" "$contract" "open-timer を報告する"
assert_output_not_contains "incomplete" "$contract" "incomplete は preempt され報告されない"
teardown

echo ""

# --- 10. 緊急度の高いチェックは両コンテキストで通知される ---
echo "[10] 緊急チェックはstop/cron両方で通知"

setup
export NIPPO_NOW="2026-03-09 10:00"
for ctx in stop cron; do
  result=$(run_check "$ctx")
  output=$(parse_output "$result")
  exit_code=$(parse_exit "$result")
  contract=$(parse_contract)
  assert_exit 1 "$exit_code" "日報未作成は${ctx}でexit 1"
  assert_output_contains "HITS=missing" "$contract" "日報未作成は${ctx}で missing"
done
teardown

setup
export NIPPO_NOW="2026-03-09 14:00"
cat >"$FIXTURE" <<'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
NIPPO
touch -t "202603091350.00" "$FIXTURE"
for ctx in stop cron; do
  result=$(run_check "$ctx")
  output=$(parse_output "$result")
  exit_code=$(parse_exit "$result")
  contract=$(parse_contract)
  assert_exit 1 "$exit_code" "未終了タイマーは${ctx}でexit 1"
  assert_output_contains "HITS=open-timer" "$contract" "未終了タイマーは${ctx}で open-timer"
done
teardown

setup
export NIPPO_NOW="2026-03-09 18:30"
cat >"$FIXTURE" <<'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [x] レビュー対応
NIPPO
touch -t "202603091820.00" "$FIXTURE"
for ctx in stop cron; do
  result=$(run_check "$ctx")
  output=$(parse_output "$result")
  exit_code=$(parse_exit "$result")
  contract=$(parse_contract)
  assert_exit 1 "$exit_code" "finalize忘れは${ctx}でexit 1"
  assert_output_contains "HITS=finalize" "$contract" "finalize忘れは${ctx}で finalize"
done
teardown

echo ""

# --- 11. 未知のコンテキストは全チェックを行う（cron相当にフォールバック） ---
echo "[11] 未知のコンテキストは全チェック"

setup
export NIPPO_NOW="2026-03-09 15:00"
cat >"$FIXTURE" <<'NIPPO'
# 2026-03-09

## Tasks:
- 10:00 🟢 start: API設計
- 11:00 🔴 end: API設計
- [ ] レビュー対応
NIPPO
touch -t "202603091450.00" "$FIXTURE"
result=$(run_check manual)
output=$(parse_output "$result")
exit_code=$(parse_exit "$result")
contract=$(parse_contract)
assert_exit 1 "$exit_code" "未知のコンテキストは低優先度も報告する"
assert_output_contains "HITS=incomplete" "$contract" "未知のコンテキストで incomplete"
assert_output_contains "CONTEXT=manual" "$contract" "契約行は渡した CONTEXT を反映する"
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
