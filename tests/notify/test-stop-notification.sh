#!/bin/bash
# Stop通知はmain chain最後の意味ある本文を1行へ整形し、長さを制限する。
# titleはrepository状態を反映しつつ、不正なcwdでも安全な既定値へ戻る。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
LIB="$SCRIPTS_DIR/lib/stop-notification.sh"

if [[ ! -f "$LIB" ]]; then
  echo "ERROR: $LIB が存在しません"
  exit 1
fi

# shellcheck source=lib/stop-notification.sh
source "$LIB"

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
}

teardown() {
  rm -rf "$TEST_DIR"
}

assert_eq() {
  local expected="$1" actual="$2" name="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected: [$expected]"
    echo "    actual:   [$actual]"
  fi
}

assert_contains() {
  local expected="$1" actual="$2" name="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == *"$expected"* ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected to contain: [$expected]"
    echo "    actual:              [$actual]"
  fi
}

assert_not_contains() {
  local unexpected="$1" actual="$2" name="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" != *"$unexpected"* ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected NOT to contain: [$unexpected]"
    echo "    actual:                  [$actual]"
  fi
}

# トランスクリプト行を組み立てるヘルパ
# 引数: <出力先> <isSidechain(true|false)> <テキスト...>
append_assistant_text() {
  local file="$1" sidechain="$2" text="$3"
  jq -cn --argjson sc "$sidechain" --arg t "$text" \
    '{type:"assistant", isSidechain:$sc, message:{content:[{type:"text", text:$t}]}}' \
    >>"$file"
}

append_tool_use() {
  local file="$1"
  jq -cn '{type:"assistant", isSidechain:false,
           message:{content:[{type:"tool_use", name:"Bash", input:{}}]}}' >>"$file"
}

append_user() {
  local file="$1" text="$2"
  jq -cn --arg t "$text" \
    '{type:"user", isSidechain:false, message:{content:[{type:"text", text:$t}]}}' >>"$file"
}

echo "=== stop-notification.sh テスト ==="
echo ""

# =============================================================================
# stop_notification_summary
# =============================================================================
echo "[1] stop_notification_summary: 最後のアシスタント発言を返す"

setup
T="$TEST_DIR/transcript.jsonl"
append_assistant_text "$T" false "最初の応答です"
append_user "$T" "次のお願い"
append_assistant_text "$T" false "実装が完了しました"
assert_eq "実装が完了しました" "$(stop_notification_summary "$T")" "最後のtextブロックを返す"
teardown

echo ""
echo "[2] stop_notification_summary: サブエージェント(isSidechain)を無視する"

setup
T="$TEST_DIR/transcript.jsonl"
append_assistant_text "$T" false "メインの最終応答"
append_assistant_text "$T" true "サブエージェントの応答"
assert_eq "メインの最終応答" "$(stop_notification_summary "$T")" "sidechainは採用しない"
teardown

echo ""
echo "[3] stop_notification_summary: tool_useのみの末尾メッセージを飛ばす"

setup
T="$TEST_DIR/transcript.jsonl"
append_assistant_text "$T" false "テストを流します"
append_tool_use "$T"
assert_eq "テストを流します" "$(stop_notification_summary "$T")" "直近のtextまで遡る"
teardown

echo ""
echo "[4] stop_notification_summary: 空文字のtextブロックを飛ばす"

setup
T="$TEST_DIR/transcript.jsonl"
append_assistant_text "$T" false "意味のある応答"
append_assistant_text "$T" false "   "
assert_eq "意味のある応答" "$(stop_notification_summary "$T")" "空白のみのtextは採用しない"
teardown

echo ""
echo "[5] stop_notification_summary: 改行を1行に畳む"

setup
T="$TEST_DIR/transcript.jsonl"
append_assistant_text "$T" false "$(printf '1行目\n\n2行目\n3行目')"
result=$(stop_notification_summary "$T")
assert_eq "1行目 2行目 3行目" "$result" "改行が空白1個に畳まれる"
assert_eq "$result" "${result//$'\n'/}" "出力に改行を含まない"
teardown

echo ""
echo "[6] stop_notification_summary: markdown記号を落とす"

setup
T="$TEST_DIR/transcript.jsonl"
# markdown記号をそのまま渡したいのでシングルクォートで固定する
# shellcheck disable=SC2016
append_assistant_text "$T" false '## 完了 **太字** と `コード` と *強調*'
result=$(stop_notification_summary "$T")
assert_not_contains '`' "$result" "バッククォートが除去される"
assert_not_contains '*' "$result" "アスタリスクが除去される"
assert_not_contains '#' "$result" "見出し記号が除去される"
assert_contains "完了" "$result" "本文は残る"
assert_contains "コード" "$result" "コード中の語は残る"
teardown

echo ""
echo "[7] stop_notification_summary: 長文を切り詰める（日本語は文字数基準）"

setup
T="$TEST_DIR/transcript.jsonl"
long=$(printf 'あ%.0s' $(seq 1 300))
append_assistant_text "$T" false "$long"
result=$(stop_notification_summary "$T")
# 120文字 + 省略記号1文字
assert_eq "121" "$(LC_ALL=C.UTF-8 bash -c 'printf "%s" "$1" | wc -m' _ "$result" | tr -d ' ')" "120文字+…に切り詰め"
assert_contains "…" "$result" "省略記号が付く"
teardown

echo ""
echo "[8] stop_notification_summary: 120文字ちょうどは切り詰めない"

setup
T="$TEST_DIR/transcript.jsonl"
exact=$(printf 'い%.0s' $(seq 1 120))
append_assistant_text "$T" false "$exact"
result=$(stop_notification_summary "$T")
assert_eq "$exact" "$result" "境界値120文字はそのまま"
teardown

echo ""
echo "[9] stop_notification_summary: フォールバック"

setup
assert_eq "タスクが完了しました" "$(stop_notification_summary "$TEST_DIR/nope.jsonl")" "存在しないパスはフォールバック"
assert_eq "タスクが完了しました" "$(stop_notification_summary "")" "空パスはフォールバック"

T="$TEST_DIR/empty.jsonl"
: >"$T"
assert_eq "タスクが完了しました" "$(stop_notification_summary "$T")" "空ファイルはフォールバック"

T2="$TEST_DIR/notext.jsonl"
append_tool_use "$T2"
assert_eq "タスクが完了しました" "$(stop_notification_summary "$T2")" "textブロックなしはフォールバック"
teardown

# =============================================================================
# stop_notification_title
# =============================================================================
echo ""
echo "[10] stop_notification_title: リポジトリ名とブランチ"

setup
REPO="$TEST_DIR/dotfiles"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name t
git -C "$REPO" commit -q --allow-empty -m init
assert_eq "✅ dotfiles (main)" "$(stop_notification_title "$REPO")" "リポジトリ名(ブランチ)"

git -C "$REPO" checkout -q -b feat/notify
assert_eq "✅ dotfiles (feat/notify)" "$(stop_notification_title "$REPO")" "ブランチ名を追従する"
teardown

echo ""
echo "[11] stop_notification_title: git管理外・不正なcwd"

setup
PLAIN="$TEST_DIR/plain-dir"
mkdir -p "$PLAIN"
assert_eq "✅ plain-dir" "$(stop_notification_title "$PLAIN")" "git管理外はディレクトリ名のみ"
assert_eq "Claude Code 完了" "$(stop_notification_title "")" "cwd空はデフォルトタイトル"
assert_eq "Claude Code 完了" "$(stop_notification_title "$TEST_DIR/nope")" "存在しないcwdはデフォルトタイトル"
teardown

# =============================================================================
echo ""
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
