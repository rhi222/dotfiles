#!/bin/bash
# setup-fish-plugins.sh のユニットテスト
#
# fish は PATH 前方の stub に差し替えて実物を呼ばない。stub は `-c` に渡された
# 文字列で分岐し、呼ばれた内容を FISH_STUB_LOG に記録する。
# ネットワークに出る経路（fisher の bootstrap / fisher update）を「呼んだか否か」で
# 検査するのがこのテストの主目的。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
TARGET="$SCRIPTS_DIR/setup/fish-plugins.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
STUB_DIR=""
PLUGINS_FILE=""
INSTALLED_FILE=""
LOG_FILE=""

setup() {
  TEST_DIR=$(mktemp -d)
  STUB_DIR="$TEST_DIR/bin"
  PLUGINS_FILE="$TEST_DIR/fish_plugins"
  INSTALLED_FILE="$TEST_DIR/installed.txt"
  LOG_FILE="$TEST_DIR/fish.log"
  mkdir -p "$STUB_DIR"
  : >"$INSTALLED_FILE"
  : >"$LOG_FILE"

  # fish stub。`fish -c '<code>'` の code を見て振る舞いを決める。
  #   functions -q fisher : FISH_STUB_HAS_FISHER で 0/1
  #   fisher list         : INSTALLED_FILE の中身を出す
  #   fisher update       : ログに残し、INSTALLED_FILE を宣言どおりに書き換える
  #                         （FISH_STUB_UPDATE_NOOP=1 なら書き換えない＝取りこぼし再現）
  #   curl ... fisher     : bootstrap。ログに残し fisher が入ったことにする
  cat >"$STUB_DIR/fish" <<'STUB'
#!/bin/bash
code="${2:-}"
echo "$code" >>"$FISH_STUB_LOG"
case "$code" in
  *"functions -q fisher"*)
    [ "${FISH_STUB_HAS_FISHER:-1}" = "1" ] && exit 0 || exit 1
    ;;
  *"fisher list"*)
    cat "$FISH_STUB_INSTALLED"
    ;;
  *"fisher update"*)
    [ "${FISH_STUB_UPDATE_FAIL:-0}" = "1" ] && exit 1
    if [ "${FISH_STUB_UPDATE_NOOP:-0}" != "1" ]; then
      cp "$FISH_STUB_DECLARED_NORM" "$FISH_STUB_INSTALLED"
    fi
    ;;
  *"fisher install"*)
    # bootstrap 経路。fisher 本体が入った状態にする
    echo "jorgebucaran/fisher" >"$FISH_STUB_INSTALLED"
    ;;
esac
exit 0
STUB
  chmod +x "$STUB_DIR/fish"
}

teardown() {
  [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# 宣言ファイルを正規化したもの（stub の update が「成功した後の状態」を作るのに使う）
write_declared_norm() {
  sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$PLUGINS_FILE" |
    grep -v '^$' | tr '[:upper:]' '[:lower:]' >"$TEST_DIR/declared-norm.txt"
}

# 引数は env 代入として渡す。スクリプト側の引数は TARGET_ARGS に入れる。
TARGET_ARGS=()
run_target() {
  write_declared_norm
  env PATH="$STUB_DIR:/usr/bin:/bin" \
    FISH_PLUGINS_FILE="$PLUGINS_FILE" \
    FISH_STUB_LOG="$LOG_FILE" \
    FISH_STUB_INSTALLED="$INSTALLED_FILE" \
    FISH_STUB_DECLARED_NORM="$TEST_DIR/declared-norm.txt" \
    "$@" bash "$TARGET" ${TARGET_ARGS+"${TARGET_ARGS[@]}"} 2>&1
}

check() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok   $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "         expected: $expected"
    echo "         actual  : $actual"
  fi
}

called_update() {
  grep -q "fisher update" "$LOG_FILE" && echo yes || echo no
}

echo "== 宣言ファイルの扱い =="

setup
out=$(env PATH="$STUB_DIR:/usr/bin:/bin" FISH_PLUGINS_FILE="$TEST_DIR/nope" \
  FISH_STUB_LOG="$LOG_FILE" bash "$TARGET" 2>&1)
check "宣言ファイルが無ければ失敗する" "1" "$?"
teardown

setup
printf '# comment only\n\n' >"$PLUGINS_FILE"
out=$(run_target)
rc=$?
check "宣言が空なら成功して何もしない（exit）" "0" "$rc"
check "宣言が空なら fisher update を呼ばない" "no" "$(called_update)"
teardown

echo "== 前提が無いとき =="

setup
printf 'jorgebucaran/fisher\n' >"$PLUGINS_FILE"
write_declared_norm
out=$(env PATH="/nonexistent" FISH_PLUGINS_FILE="$PLUGINS_FILE" \
  FISH_STUB_LOG="$LOG_FILE" /bin/bash "$TARGET" 2>&1)
check "fish が無ければ既定では警告して成功する" "0" "$?"
teardown

setup
printf 'jorgebucaran/fisher\n' >"$PLUGINS_FILE"
write_declared_norm
out=$(env PATH="/nonexistent" FISH_PLUGINS_FILE="$PLUGINS_FILE" \
  FISH_STUB_LOG="$LOG_FILE" STRICT=1 /bin/bash "$TARGET" 2>&1)
check "fish が無く STRICT=1 なら失敗する" "1" "$?"
teardown

echo "== 差分がないときはネットワークに出ない =="

setup
printf 'jorgebucaran/fisher\npatrickf1/fzf.fish\n' >"$PLUGINS_FILE"
printf 'jorgebucaran/fisher\npatrickf1/fzf.fish\n' >"$INSTALLED_FILE"
out=$(run_target)
check "揃っていれば成功する" "0" "$?"
check "揃っていれば fisher update を呼ばない" "no" "$(called_update)"
teardown

echo "== 差分があるとき =="

setup
printf 'jorgebucaran/fisher\npatrickf1/fzf.fish\n' >"$PLUGINS_FILE"
printf 'jorgebucaran/fisher\n' >"$INSTALLED_FILE"
out=$(run_target)
check "未導入があれば成功する" "0" "$?"
check "未導入があれば fisher update を呼ぶ" "yes" "$(called_update)"
teardown

setup
printf 'jorgebucaran/fisher\n' >"$PLUGINS_FILE"
printf 'jorgebucaran/fisher\nsomeone/undeclared\n' >"$INSTALLED_FILE"
out=$(run_target)
check "未宣言のものがあれば fisher update を呼ぶ" "yes" "$(called_update)"
# fisher update は未宣言を削除する。黙って消すと事故なので事前に名前を出す
check "未宣言のものを名指しで報告する" "yes" \
  "$(printf '%s' "$out" | grep -q 'someone/undeclared' && echo yes || echo no)"
teardown

echo "== --dry-run =="

setup
printf 'jorgebucaran/fisher\npatrickf1/fzf.fish\n' >"$PLUGINS_FILE"
printf 'jorgebucaran/fisher\n' >"$INSTALLED_FILE"
TARGET_ARGS=(--dry-run)
out=$(run_target)
check "--dry-run は成功する" "0" "$?"
check "--dry-run は fisher update を呼ばない" "no" "$(called_update)"
TARGET_ARGS=()
teardown

echo "== fisher 本体が未導入 =="

setup
printf 'jorgebucaran/fisher\npatrickf1/fzf.fish\n' >"$PLUGINS_FILE"
out=$(run_target FISH_STUB_HAS_FISHER=0)
check "fisher が無ければ bootstrap する" "yes" \
  "$(grep -q 'fisher install' "$LOG_FILE" && echo yes || echo no)"
check "bootstrap 後に fisher update まで進む" "yes" "$(called_update)"
teardown

setup
printf 'jorgebucaran/fisher\n' >"$PLUGINS_FILE"
write_declared_norm
out=$(env PATH="$STUB_DIR:/usr/bin:/bin" FISH_PLUGINS_FILE="$PLUGINS_FILE" \
  FISH_STUB_LOG="$LOG_FILE" FISH_STUB_INSTALLED="$INSTALLED_FILE" \
  FISH_STUB_DECLARED_NORM="$TEST_DIR/declared-norm.txt" \
  FISH_STUB_HAS_FISHER=0 bash "$TARGET" --dry-run 2>&1)
check "--dry-run なら bootstrap もしない" "no" \
  "$(grep -q 'fisher install' "$LOG_FILE" && echo yes || echo no)"
teardown

echo "== 終了コードを信じない =="

setup
printf 'jorgebucaran/fisher\npatrickf1/fzf.fish\n' >"$PLUGINS_FILE"
printf 'jorgebucaran/fisher\n' >"$INSTALLED_FILE"
out=$(run_target FISH_STUB_UPDATE_NOOP=1)
# update が緑で返っても実体が増えていなければ失敗として扱う
check "update が成功しても揃っていなければ失敗する" "1" "$?"
teardown

setup
printf 'jorgebucaran/fisher\npatrickf1/fzf.fish\n' >"$PLUGINS_FILE"
printf 'jorgebucaran/fisher\n' >"$INSTALLED_FILE"
out=$(run_target FISH_STUB_UPDATE_FAIL=1)
check "fisher update 自体が失敗すれば失敗する" "1" "$?"
teardown

echo "== 行の解釈 =="

setup
printf '# 先頭コメント\n\njorgebucaran/fisher   # 行末コメント\n  patrickf1/fzf.fish  \n' >"$PLUGINS_FILE"
printf 'jorgebucaran/fisher\npatrickf1/fzf.fish\n' >"$INSTALLED_FILE"
out=$(run_target)
check "コメント・空行・前後空白を落とす" "no" "$(called_update)"
teardown

setup
printf 'Jorgebucaran/Fisher\n' >"$PLUGINS_FILE"
printf 'jorgebucaran/fisher\n' >"$INSTALLED_FILE"
out=$(run_target)
# fisher は plugin 名を string lower して保持するので、比較も小文字で行う
check "大文字小文字の違いは同一とみなす" "no" "$(called_update)"
teardown

echo "== 実際の宣言ファイル =="

REAL_FILE="$REPO_ROOT/.config/fish/fish_plugins"
TOTAL=$((TOTAL + 1))
if [[ -f "$REAL_FILE" ]]; then
  PASS=$((PASS + 1))
  echo "  ok   .config/fish/fish_plugins が存在する"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL .config/fish/fish_plugins が存在する"
fi

check "fisher 自身が宣言されている" "yes" \
  "$(grep -qi '^jorgebucaran/fisher$' "$REAL_FILE" 2>/dev/null && echo yes || echo no)"

echo
echo "結果: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
