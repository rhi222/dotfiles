#!/bin/bash
# setup-gh-extensions.sh のユニットテスト
# PATH先頭に gh のスタブを置き、実際のGitHubアクセスなしで挙動を検証する
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
SETUP="$SCRIPTS_DIR/setup-gh-extensions.sh"

if [[ ! -f "$SETUP" ]]; then
  echo "ERROR: $SETUP が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
BIN_DIR=""
EXT_FILE=""
GH_LOG=""
INSTALLED_FILE=""

# gh スタブを用意する。
#   $GH_LOG           : 呼び出された引数を1行ずつ記録
#   $GH_INSTALLED     : `gh extension list` が返す内容
#   $GH_INSTALL_EXIT  : `gh extension install` の終了コード（既定0）
#   $GH_MISSING=1     : gh 自体を PATH から消す
setup() {
  TEST_DIR=$(mktemp -d)
  BIN_DIR="$TEST_DIR/bin"
  mkdir -p "$BIN_DIR"
  EXT_FILE="$TEST_DIR/gh-extensions.txt"
  GH_LOG="$TEST_DIR/gh.log"
  INSTALLED_FILE="$TEST_DIR/installed.txt"
  : >"$GH_LOG"
  : >"$INSTALLED_FILE"

  cat >"$BIN_DIR/gh" <<'STUB'
#!/bin/bash
echo "$*" >>"$GH_LOG"
case "$1 ${2:-}" in
  "--version ")   echo "gh version 2.97.0 (2026-07-31)" ;;
  "auth status")  exit "${GH_AUTH_EXIT:-0}" ;;
  "extension list") cat "$GH_INSTALLED" ;;
  "extension install") exit "${GH_INSTALL_EXIT:-0}" ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$BIN_DIR/gh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# スタブ入りPATHでsetupスクリプトを実行し、出力をechoして終了コードを返す
# GH_MISSING=1 のときはPATHを空ディレクトリだけにする（実gh /usr/bin/gh を拾わせない）。
# setup-gh-extensions.sh はbash builtinのみで書かれているのでこれで動く。
run_setup() {
  local path="$BIN_DIR:$PATH"
  [[ "${GH_MISSING:-0}" == "1" ]] && path="$BIN_DIR/empty"
  env PATH="$path" \
    GH_LOG="$GH_LOG" \
    GH_INSTALLED="$INSTALLED_FILE" \
    GH_INSTALL_EXIT="${GH_INSTALL_EXIT:-0}" \
    GH_AUTH_EXIT="${GH_AUTH_EXIT:-0}" \
    GH_EXTENSIONS_FILE="$EXT_FILE" \
    STRICT="${STRICT:-0}" \
    /bin/bash "$SETUP" "$@" 2>&1
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

assert_not_contains() {
  local unexpected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$actual" | grep -qF "$unexpected"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    should NOT contain: $unexpected"
    echo "    actual: $actual"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  fi
}

echo "=== setup-gh-extensions.sh テスト ==="
echo ""

# --- 1. 未インストールの拡張をインストールする ---
echo "[1] 未インストールの拡張"
setup
printf 'github/gh-stack\n' >"$EXT_FILE"
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 0 "$exit_code" "正常終了はexit 0"
assert_contains "extension install github/gh-stack" "$(cat "$GH_LOG")" "install が呼ばれる"
teardown
echo ""

# --- 2. インストール済みはskip ---
echo "[2] インストール済み"
setup
printf 'github/gh-stack\n' >"$EXT_FILE"
printf 'gh stack\tgithub/gh-stack\tv0.1.0\n' >"$INSTALLED_FILE"
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 0 "$exit_code" "skipでもexit 0"
assert_contains "skip" "$output" "skip が表示される"
assert_not_contains "extension install" "$(cat "$GH_LOG")" "install は呼ばれない"
teardown
echo ""

# --- 3. コメント・空行・インラインコメントを無視 ---
echo "[3] コメントと空行"
setup
cat >"$EXT_FILE" <<'EOF'
# 先頭コメント

github/gh-stack  # インラインコメント
   # インデントされたコメント
EOF
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 0 "$exit_code" "exit 0"
assert_contains "extension install github/gh-stack" "$(cat "$GH_LOG")" "インラインコメントを除いて解釈する"
assert_eq 1 "$(grep -c 'extension install' "$GH_LOG")" "installの呼び出しは1回だけ"
teardown
echo ""

# --- 4. @version 指定は --pin に変換される ---
echo "[4] バージョン指定"
setup
printf 'github/gh-stack@v0.1.0\n' >"$EXT_FILE"
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 0 "$exit_code" "exit 0"
assert_contains "extension install github/gh-stack --pin v0.1.0" "$(cat "$GH_LOG")" "--pin が渡る"
teardown
echo ""

# --- 5. 不正な行は失敗扱い ---
echo "[5] 不正な行"
setup
printf 'gh-stack\n' >"$EXT_FILE"
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 1 "$exit_code" "owner/repo 形式でなければexit 1"
assert_contains "malformed" "$output" "malformed を報告する"
assert_not_contains "extension install" "$(cat "$GH_LOG")" "installは呼ばれない"
teardown
echo ""

# --- 6. install失敗は集約されてexit 1 ---
echo "[6] install失敗"
setup
printf 'github/gh-stack\n' >"$EXT_FILE"
GH_INSTALL_EXIT=1
exit_code=0
output=$(run_setup) || exit_code=$?
GH_INSTALL_EXIT=0
assert_eq 1 "$exit_code" "install失敗はexit 1"
assert_contains "Failed" "$output" "失敗一覧を出力する"
teardown
echo ""

# --- 7. dry-run は install しない ---
echo "[7] dry-run"
setup
printf 'github/gh-stack\n' >"$EXT_FILE"
exit_code=0
output=$(run_setup --dry-run) || exit_code=$?
assert_eq 0 "$exit_code" "exit 0"
assert_contains "[dry-run]" "$output" "[dry-run] 表示を含む"
assert_not_contains "extension install" "$(cat "$GH_LOG")" "installは呼ばれない"
teardown
echo ""

# --- 8. gh不在: 非STRICTは警告してexit 0 / STRICT=1はexit 1 ---
echo "[8] gh不在"
setup
printf 'github/gh-stack\n' >"$EXT_FILE"
mkdir -p "$BIN_DIR/empty"
GH_MISSING=1
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 0 "$exit_code" "非STRICTはexit 0"
assert_contains "Warning" "$output" "警告を出力する"

STRICT=1
exit_code=0
output=$(run_setup) || exit_code=$?
STRICT=0
assert_eq 1 "$exit_code" "STRICT=1はexit 1"
assert_contains "Error" "$output" "エラーを出力する"
GH_MISSING=0
teardown
echo ""

# --- 9. 宣言ファイルが無ければエラー ---
echo "[9] 宣言ファイル不在"
setup
rm -f "$EXT_FILE"
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 1 "$exit_code" "ファイル不在はexit 1"
assert_contains "not found" "$output" "not found を報告する"
teardown
echo ""

# --- 10. 実際の gh-extensions.txt がパースできる ---
echo "[10] 実ファイルの妥当性"
TOTAL=$((TOTAL + 1))
real_file="$SCRIPTS_DIR/gh-extensions.txt"
if [[ ! -f "$real_file" ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: $real_file が存在しない"
else
  bad=$(grep -vE '^\s*(#|$)' "$real_file" | sed -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' |
    grep -vE '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(@[A-Za-z0-9_.-]+)?$' || true)
  if [[ -n "$bad" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: 不正な行がある: $bad"
  else
    PASS=$((PASS + 1))
    echo "  PASS: 全行が owner/repo[@version] 形式"
  fi
fi
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
