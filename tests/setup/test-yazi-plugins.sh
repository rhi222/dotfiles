#!/bin/bash
# setup-yazi-plugins.sh のユニットテスト
# PATH先頭に ya のスタブを置き、実際のGitHubアクセスなしで挙動を検証する
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
SETUP="$SCRIPTS_DIR/setup-yazi-plugins.sh"

if [[ ! -f "$SETUP" ]]; then
  echo "ERROR: $SETUP が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
BIN_DIR=""
CONFIG_DIR=""
PACKAGE_FILE=""
YA_LOG=""

# ya スタブを用意する。
#   $YA_LOG            : 呼び出された引数を1行ずつ記録
#   $YA_DEPLOY_NAMES   : `ya pkg install` が実体を作るパッケージ名（空なら何も作らない）
#   $YA_INSTALL_EXIT   : `ya pkg install` の終了コード（既定0）
#   $YA_MISSING=1      : ya 自体を PATH から消す
setup() {
  TEST_DIR=$(mktemp -d)
  BIN_DIR="$TEST_DIR/bin"
  CONFIG_DIR="$TEST_DIR/config/yazi"
  mkdir -p "$BIN_DIR" "$BIN_DIR/empty" "$CONFIG_DIR"
  PACKAGE_FILE="$CONFIG_DIR/package.toml"
  YA_LOG="$TEST_DIR/ya.log"
  : >"$YA_LOG"

  # 本物の `ya pkg install` は package.toml の宣言を plugins/<name>.yazi へ展開する。
  # スタブでは YA_DEPLOY_NAMES で明示された分だけを作り、「installは成功したが
  # 実体が入らなかった」状態も再現できるようにする。
  cat >"$BIN_DIR/ya" <<'STUB'
#!/bin/bash
echo "$*" >>"$YA_LOG"
case "$1 ${2:-}" in
  "pkg install")
    for name in ${YA_DEPLOY_NAMES:-}; do
      mkdir -p "$YAZI_CONFIG_HOME/plugins/$name.yazi"
    done
    exit "${YA_INSTALL_EXIT:-0}"
    ;;
  "--version ") echo "Ya 26.5.6 (aa52643 2026-05-05)" ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$BIN_DIR/ya"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# 宣言された名前の実体を作る（= 既にインストール済みの状態にする）
deploy() {
  local kind="$1"
  shift
  local name
  for name in "$@"; do
    mkdir -p "$CONFIG_DIR/$kind/$name.yazi"
  done
}

# スタブ入りPATHでsetupスクリプトを実行し、出力をechoして終了コードを返す。
# YA_MISSING=1 のときはPATHを空ディレクトリだけにする（実 ya を拾わせない）。
# setup-yazi-plugins.sh はbash builtinのみで書かれているのでこれで動く。
run_setup() {
  local path="$BIN_DIR:$PATH"
  [[ "${YA_MISSING:-0}" == "1" ]] && path="$BIN_DIR/empty"
  env PATH="$path" \
    YA_LOG="$YA_LOG" \
    YA_DEPLOY_NAMES="${YA_DEPLOY_NAMES:-}" \
    YA_INSTALL_EXIT="${YA_INSTALL_EXIT:-0}" \
    YAZI_CONFIG_HOME="$CONFIG_DIR" \
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

echo "=== setup-yazi-plugins.sh テスト ==="
echo ""

# --- 1. 実体が無いときインストールする ---
echo "[1] 実体が無い"
setup
printf '[[plugin.deps]]\nuse = "yazi-rs/plugins:git"\nrev = "ac82af3"\n' >"$PACKAGE_FILE"
YA_DEPLOY_NAMES="git"
exit_code=0
output=$(run_setup) || exit_code=$?
YA_DEPLOY_NAMES=""
assert_eq 0 "$exit_code" "正常終了はexit 0"
assert_contains "pkg install" "$(cat "$YA_LOG")" "ya pkg install が呼ばれる"
assert_contains "git" "$output" "欠けているパッケージ名を表示する"
teardown
echo ""

# --- 2. 実体が揃っていればインストールしない ---
echo "[2] 実体が揃っている"
setup
printf '[[plugin.deps]]\nuse = "yazi-rs/plugins:git"\n' >"$PACKAGE_FILE"
deploy plugins git
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 0 "$exit_code" "skipでもexit 0"
assert_contains "up to date" "$output" "最新である旨を表示する"
assert_not_contains "pkg install" "$(cat "$YA_LOG")" "installは呼ばれない"
teardown
echo ""

# --- 3. 一部だけ欠けていてもインストールする ---
echo "[3] 一部が欠けている"
setup
printf '[[plugin.deps]]\nuse = "yazi-rs/plugins:git"\n\n[[plugin.deps]]\nuse = "yazi-rs/plugins:smart-enter"\n' >"$PACKAGE_FILE"
deploy plugins git
YA_DEPLOY_NAMES="smart-enter"
exit_code=0
output=$(run_setup) || exit_code=$?
YA_DEPLOY_NAMES=""
assert_eq 0 "$exit_code" "exit 0"
assert_contains "pkg install" "$(cat "$YA_LOG")" "installが呼ばれる"
assert_contains "smart-enter" "$output" "欠けている方を名指しする"
teardown
echo ""

# --- 4. flavor も実体として数える ---
echo "[4] flavor"
setup
printf '[[flavor.deps]]\nuse = "yazi-rs/flavors:catppuccin-mocha"\n' >"$PACKAGE_FILE"
deploy flavors catppuccin-mocha
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 0 "$exit_code" "exit 0"
assert_not_contains "pkg install" "$(cat "$YA_LOG")" "flavors/ にあればinstallしない"
teardown
echo ""

# --- 5. `owner/repo` 形式（サブパスなし）はrepo名で解決する ---
echo "[5] サブパスなしの use"
setup
printf '[[plugin.deps]]\nuse = "someone/relative-motions.yazi"\n' >"$PACKAGE_FILE"
deploy plugins relative-motions
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 0 "$exit_code" "exit 0"
assert_not_contains "pkg install" "$(cat "$YA_LOG")" ".yazi サフィックスを外して突き合わせる"
teardown
echo ""

# --- 6. dry-run は install しない ---
echo "[6] dry-run"
setup
printf '[[plugin.deps]]\nuse = "yazi-rs/plugins:git"\n' >"$PACKAGE_FILE"
exit_code=0
output=$(run_setup --dry-run) || exit_code=$?
assert_eq 0 "$exit_code" "exit 0"
assert_contains "[dry-run]" "$output" "[dry-run] 表示を含む"
assert_not_contains "pkg install" "$(cat "$YA_LOG")" "installは呼ばれない"
teardown
echo ""

# --- 7. install が失敗したらexit 1 ---
echo "[7] install失敗"
setup
printf '[[plugin.deps]]\nuse = "yazi-rs/plugins:git"\n' >"$PACKAGE_FILE"
YA_INSTALL_EXIT=1
exit_code=0
output=$(run_setup) || exit_code=$?
YA_INSTALL_EXIT=0
assert_eq 1 "$exit_code" "install失敗はexit 1"
assert_contains "Error" "$output" "エラーを出力する"
teardown
echo ""

# --- 8. install成功でも実体が入らなければexit 1 ---
# 今回の障害（宣言はあるのに plugins/ が空で init.lua の require が落ちる）を
# 検知するための回帰テスト。ya の終了コードだけを信じない。
echo "[8] install成功だが実体が入らない"
setup
printf '[[plugin.deps]]\nuse = "yazi-rs/plugins:git"\n' >"$PACKAGE_FILE"
YA_DEPLOY_NAMES=""
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 1 "$exit_code" "実体が無ければexit 1"
assert_contains "pkg install" "$(cat "$YA_LOG")" "installは試みる"
assert_contains "still missing" "$output" "未解決のまま残った旨を報告する"
teardown
echo ""

# --- 9. ya不在: 非STRICTは警告してexit 0 / STRICT=1はexit 1 ---
echo "[9] ya不在"
setup
printf '[[plugin.deps]]\nuse = "yazi-rs/plugins:git"\n' >"$PACKAGE_FILE"
YA_MISSING=1
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
YA_MISSING=0
teardown
echo ""

# --- 10. package.toml が無ければ何もせず正常終了 ---
# yazi を使わない端末や、リンク前に呼ばれた場合に落ちないようにする。
echo "[10] package.toml不在"
setup
rm -f "$PACKAGE_FILE"
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 0 "$exit_code" "宣言が無ければexit 0"
assert_contains "no package.toml" "$output" "宣言不在を報告する"
assert_not_contains "pkg install" "$(cat "$YA_LOG")" "installは呼ばれない"
teardown
echo ""

# --- 11. 宣言が空なら install しない ---
echo "[11] 宣言が空"
setup
printf '[flavor]\ndeps = []\n' >"$PACKAGE_FILE"
exit_code=0
output=$(run_setup) || exit_code=$?
assert_eq 0 "$exit_code" "exit 0"
assert_not_contains "pkg install" "$(cat "$YA_LOG")" "installは呼ばれない"
teardown
echo ""

# --- 12. 未知の引数はexit 2 ---
echo "[12] 未知の引数"
setup
printf '[[plugin.deps]]\nuse = "yazi-rs/plugins:git"\n' >"$PACKAGE_FILE"
exit_code=0
output=$(run_setup --nope) || exit_code=$?
assert_eq 2 "$exit_code" "未知の引数はexit 2"
teardown
echo ""

# --- 13. YAZI_CONFIG_HOME 未設定なら XDG_CONFIG_HOME/yazi を見る ---
echo "[13] XDG_CONFIG_HOME フォールバック"
setup
printf '[[plugin.deps]]\nuse = "yazi-rs/plugins:git"\n' >"$PACKAGE_FILE"
deploy plugins git
exit_code=0
output=$(env -u YAZI_CONFIG_HOME PATH="$BIN_DIR:$PATH" \
  YA_LOG="$YA_LOG" XDG_CONFIG_HOME="$TEST_DIR/config" \
  /bin/bash "$SETUP" 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "exit 0"
assert_contains "up to date" "$output" "XDG_CONFIG_HOME/yazi を設定ディレクトリとして解決する"
teardown
echo ""

# --- 14. 実際の package.toml が解釈できる ---
echo "[14] 実ファイルの妥当性"
TOTAL=$((TOTAL + 1))
real_file="$REPO_ROOT/.config/yazi/package.toml"
if [[ ! -f "$real_file" ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: $real_file が存在しない"
else
  bad=$(grep -E '^\s*use\s*=' "$real_file" |
    grep -vE '^\s*use\s*=\s*"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(:[A-Za-z0-9_.-]+)?"\s*$' || true)
  if [[ -n "$bad" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: 解釈できない use 行がある: $bad"
  else
    PASS=$((PASS + 1))
    echo "  PASS: 全ての use 行が owner/repo[:name] 形式"
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
