#!/bin/bash
# lib/notify-cooldown.sh のユニットテスト
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
LIB="$SCRIPTS_DIR/lib/notify-cooldown.sh"

if [[ ! -f "$LIB" ]]; then
  echo "ERROR: $LIB が存在しません"
  exit 1
fi

# shellcheck source=lib/notify-cooldown.sh
source "$LIB"

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
STATE=""

setup() {
  TEST_DIR=$(mktemp -d)
  STATE="$TEST_DIR/state"
  export NOTIFY_COOLDOWN_SEC=3600
}

teardown() {
  rm -rf "$TEST_DIR"
  unset NOTIFY_COOLDOWN_SEC
  unset NOTIFY_COOLDOWN_NOW
}

assert_send() {
  local name="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if notify_cooldown_should_send "$@"; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (送信されるべきだが抑止された)"
  fi
}

assert_suppress() {
  local name="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if notify_cooldown_should_send "$@"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (抑止されるべきだが送信された)"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  fi
}

echo "=== notify-cooldown.sh テスト ==="
echo ""

# --- 1. 初回は必ず送る ---
echo "[1] 初回送信"

setup
export NOTIFY_COOLDOWN_NOW=1000000
assert_send "state未作成なら送信" "$STATE" "📋 未完了タスク: 3件"
TOTAL=$((TOTAL + 1))
if [[ -f "$STATE" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: stateファイルが作成される"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: stateファイルが作成されていない"
fi
teardown

echo ""

# --- 2. クールダウン内の同一メッセージは抑止 ---
echo "[2] クールダウン内の重複抑止"

setup
export NOTIFY_COOLDOWN_NOW=1000000
assert_send "1回目" "$STATE" "📋 未完了タスク: 3件"
export NOTIFY_COOLDOWN_NOW=1000001
assert_suppress "1秒後の同一メッセージ" "$STATE" "📋 未完了タスク: 3件"
export NOTIFY_COOLDOWN_NOW=1003599
assert_suppress "3599秒後の同一メッセージ" "$STATE" "📋 未完了タスク: 3件"
teardown

echo ""

# --- 3. クールダウン経過後は送る（境界値） ---
echo "[3] クールダウン経過"

setup
export NOTIFY_COOLDOWN_NOW=1000000
assert_send "1回目" "$STATE" "📋 未完了タスク: 3件"
export NOTIFY_COOLDOWN_NOW=1003600
assert_send "ちょうど3600秒後は送信" "$STATE" "📋 未完了タスク: 3件"
export NOTIFY_COOLDOWN_NOW=1003601
assert_suppress "再送直後は再び抑止" "$STATE" "📋 未完了タスク: 3件"
teardown

echo ""

# --- 4. 内容が変わったらクールダウン内でも送る ---
echo "[4] メッセージ変化時は即送信"

setup
export NOTIFY_COOLDOWN_NOW=1000000
assert_send "1回目" "$STATE" "📋 未完了タスク: 3件"
export NOTIFY_COOLDOWN_NOW=1000010
assert_send "件数が変わったら送信" "$STATE" "📋 未完了タスク: 5件"
assert_suppress "新しい内容で再び抑止" "$STATE" "📋 未完了タスク: 5件"
teardown

echo ""

# --- 5. 抑止時にクールダウン窓が延びない ---
echo "[5] 抑止してもタイムスタンプを更新しない"

setup
export NOTIFY_COOLDOWN_NOW=1000000
assert_send "1回目" "$STATE" "同じメッセージ"
# 途中で何度も抑止されても、最初の送信から3600秒で解ける
for t in 1001000 1002000 1003000; do
  export NOTIFY_COOLDOWN_NOW="$t"
  notify_cooldown_should_send "$STATE" "同じメッセージ" >/dev/null 2>&1
done
export NOTIFY_COOLDOWN_NOW=1003600
assert_send "初回送信から3600秒で解ける" "$STATE" "同じメッセージ"
teardown

echo ""

# --- 6. NOTIFY_COOLDOWN_SEC を尊重する ---
echo "[6] クールダウン秒数の設定"

setup
export NOTIFY_COOLDOWN_SEC=60
export NOTIFY_COOLDOWN_NOW=1000000
assert_send "1回目" "$STATE" "メッセージ"
export NOTIFY_COOLDOWN_NOW=1000059
assert_suppress "59秒後は抑止" "$STATE" "メッセージ"
export NOTIFY_COOLDOWN_NOW=1000060
assert_send "60秒後は送信" "$STATE" "メッセージ"
teardown

echo ""

# --- 7. 親ディレクトリを自動生成する ---
echo "[7] 親ディレクトリ自動生成"

setup
export NOTIFY_COOLDOWN_NOW=1000000
NESTED="$TEST_DIR/a/b/c/state"
assert_send "深いパスでも送信" "$NESTED" "メッセージ"
TOTAL=$((TOTAL + 1))
if [[ -f "$NESTED" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: ネストしたstateファイルが作成される"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: ネストしたstateファイルが作成されていない"
fi
teardown

echo ""

# --- 8. 壊れたstateファイルは送信側に倒す ---
echo "[8] 壊れたstateファイル"

setup
export NOTIFY_COOLDOWN_NOW=1000000
echo "ゴミデータ" >"$STATE"
assert_send "数値でないタイムスタンプなら送信" "$STATE" "メッセージ"
assert_suppress "送信後は正常なstateとして扱われる" "$STATE" "メッセージ"
teardown

echo ""

# --- 9. 改行やタブを含むメッセージ ---
echo "[9] 特殊文字を含むメッセージ"

setup
export NOTIFY_COOLDOWN_NOW=1000000
MSG=$(printf '1行目\tタブ\n2行目')
assert_send "改行タブ入りの1回目" "$STATE" "$MSG"
assert_suppress "改行タブ入りの重複を検出" "$STATE" "$MSG"
assert_send "1行目だけの別メッセージは送信" "$STATE" "1行目"
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
