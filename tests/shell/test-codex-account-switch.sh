#!/bin/bash
# Codex CLIが対象repositoryで誤ったaccount homeへfallbackしないことを固定するテスト。
# repository外・対象外では呼び出し元のCODEX_HOMEと引数・終了コードを維持する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CODEX_FUNCTION="$REPO_ROOT/.config/fish/my/functions/codex.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
BIN_DIR="$TEST_DIR/bin"
TARGET_REPO="$TEST_DIR/target repo"
OTHER_REPO="$TEST_DIR/other-repo"
WORKTREE_ROOT="$TEST_DIR/worktree-topic"
OUTSIDE_DIR="$TEST_DIR/outside"
ALT_HOME="$TEST_DIR/private codex home"
INHERITED_HOME="$TEST_DIR/default-codex-home"
LOG_FILE="$TEST_DIR/codex.log"
ERR_FILE="$TEST_DIR/codex.err"

mkdir -p "$BIN_DIR" "$TARGET_REPO/sub dir" "$OTHER_REPO" "$WORKTREE_ROOT" \
  "$OUTSIDE_DIR" "$ALT_HOME" "$INHERITED_HOME"
git -C "$TARGET_REPO" init -q
git -C "$OTHER_REPO" init -q
git -C "$WORKTREE_ROOT" init -q

cat >"$BIN_DIR/codex" <<'STUB'
#!/bin/bash
{
  echo call
  if [[ -v CODEX_HOME ]]; then
    echo home_set=yes
    printf 'home=<%s>\n' "$CODEX_HOME"
  else
    echo home_set=no
  fi
  index=1
  for arg in "$@"; do
    printf 'arg[%d]=<%s>\n' "$index" "$arg"
    index=$((index + 1))
  done
} >>"$CODEX_TEST_LOG"
exit "${CODEX_TEST_RC:-0}"
STUB
chmod +x "$BIN_DIR/codex"

PASS=0
FAIL=0
TOTAL=0

check_eq() {
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

check_contains() {
  local name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  ok   $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "         missing: $needle"
    echo "         actual : $haystack"
  fi
}

invoke() {
  local cwd="$1" inherited_home="$2" alt_home="$3"
  shift 3
  : >"$LOG_FILE"
  : >"$ERR_FILE"
  local -a env_options=()
  local -a env_vars=(
    "PATH=$BIN_DIR:$PATH"
    "CODEX_TEST_LOG=$LOG_FILE"
    "TEST_CODEX_FUNCTION=$CODEX_FUNCTION"
    "TEST_TARGET_REPO=$TARGET_REPO"
    "TEST_WORKTREE_ROOT=$WORKTREE_ROOT"
  )
  if [[ "$inherited_home" == __UNSET__ ]]; then
    env_options+=("-u" "CODEX_HOME")
  else
    env_vars+=("CODEX_HOME=$inherited_home")
  fi
  if [[ "$alt_home" != __UNSET__ ]]; then
    env_vars+=("TEST_ALT_HOME=$alt_home")
  else
    env_options+=("-u" "TEST_ALT_HOME")
  fi

  (
    cd "$cwd" || exit
    env "${env_options[@]}" "${env_vars[@]}" fish --no-config -c '
      source $TEST_CODEX_FUNCTION
      set -g codex_alt_repo_roots $TEST_TARGET_REPO $TEST_WORKTREE_ROOT
      if set -q TEST_ALT_HOME
        set -g codex_alt_home $TEST_ALT_HOME
      end
      codex $argv
    ' "$@" 2>"$ERR_FILE"
  )
}

echo "== 対象repositoryは専用homeを使う =="
invoke "$TARGET_REPO" "$INHERITED_HOME" "$ALT_HOME" exec 'hello world' '*.md'
check_contains "rootで専用home" "home=<$ALT_HOME>" "$(cat "$LOG_FILE")"
check_contains "空白を含む引数" "arg[2]=<hello world>" "$(cat "$LOG_FILE")"
check_contains "glob文字を展開しない" "arg[3]=<*.md>" "$(cat "$LOG_FILE")"
check_eq "fake Codexを1回だけ呼ぶ" "1" "$(grep -c '^call$' "$LOG_FILE")"

invoke "$TARGET_REPO/sub dir" "$INHERITED_HOME" "$ALT_HOME" resume
check_contains "subdirectoryで専用home" "home=<$ALT_HOME>" "$(cat "$LOG_FILE")"
check_contains "resumeをそのまま渡す" "arg[1]=<resume>" "$(cat "$LOG_FILE")"

invoke "$WORKTREE_ROOT" "$INHERITED_HOME" "$ALT_HOME" login status
check_contains "登録済みworktreeで専用home" "home=<$ALT_HOME>" "$(cat "$LOG_FILE")"
check_contains "login statusをそのまま渡す" "arg[1]=<login>" "$(cat "$LOG_FILE")"
check_contains "複数引数を保つ" "arg[2]=<status>" "$(cat "$LOG_FILE")"

echo "== 対象外では呼び出し元のhomeを維持する =="
invoke "$OTHER_REPO" "$INHERITED_HOME" "$ALT_HOME"
check_contains "別repositoryは継承home" "home=<$INHERITED_HOME>" "$(cat "$LOG_FILE")"

invoke "$OUTSIDE_DIR" "$INHERITED_HOME" "$ALT_HOME"
check_contains "repository外は継承home" "home=<$INHERITED_HOME>" "$(cat "$LOG_FILE")"

invoke "$OTHER_REPO" __UNSET__ "$ALT_HOME"
check_contains "未設定のCODEX_HOMEを設定しない" "home_set=no" "$(cat "$LOG_FILE")"

echo "== 設定不足と終了コードを保つ =="
if invoke "$TARGET_REPO" "$INHERITED_HOME" __UNSET__; then
  missing_rc=0
else
  missing_rc=$?
fi
check_eq "専用home未設定は非0" "2" "$missing_rc"
check_eq "設定不足ではCodexを呼ばない" "0" "$(grep -c '^call$' "$LOG_FILE" || true)"
check_contains "fallback拒否を案内する" "fallbackを拒否" "$(cat "$ERR_FILE")"

export CODEX_TEST_RC=37
if invoke "$OTHER_REPO" "$INHERITED_HOME" "$ALT_HOME" exec; then
  codex_rc=0
else
  codex_rc=$?
fi
unset CODEX_TEST_RC
check_eq "Codexの非0終了コードを返す" "37" "$codex_rc"

echo
echo "結果: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
