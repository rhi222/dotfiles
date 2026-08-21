#!/bin/bash
# sync-windows-settings.sh（互換 wrapper）の契約を検査する。
#
# **実装の振る舞いは Go 側が持つ**（internal/settings の unit test）。
# .wslconfig を素通しすること・Terminal の JSON を正規化すること・JSONC を
# 弾くこと・push の安全弁はすべてそちらにある。ここは wrapper の転送と、
# target の選択・複数対象の扱いだけを見る。
#
# **実ファイルのパスは環境変数で差し替える。** /mnt/c に触らずに済むようにするため。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
TARGET="$SCRIPTS_DIR/sync-windows-settings.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET が存在しません"
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "SKIP: go が無いので dotctl をビルドできない"
  exit 0
fi

PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
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

has() { grep -q -- "$1" <<<"$2" && echo yes || echo no; }

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
FAKE_HOME="$TEST_DIR/fakehome"
mkdir -p "$FAKE_HOME"

if ! (cd "$REPO_ROOT" && go build -o "$TEST_DIR/dotctl" ./cmd/dotctl) 2>"$TEST_DIR/build.err"; then
  echo "ERROR: dotctl のビルドに失敗"
  cat "$TEST_DIR/build.err"
  exit 1
fi

W_LIVE="$TEST_DIR/w-live"
W_REPO="$TEST_DIR/w-repo"
T_LIVE="$TEST_DIR/t-live.json"
T_REPO="$TEST_DIR/t-repo.json"

run() {
  env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" \
    WSLCONFIG_LIVE="$W_LIVE" WSLCONFIG_REPO="$W_REPO" \
    WT_SETTINGS_LIVE="$T_LIVE" WT_SETTINGS_REPO="$T_REPO" \
    bash "$TARGET" "$@" 2>&1
}

printf '[wsl2]\n# 16GB 機で Windows 側に 4GB 残す実測値\nmemory=12GB\n' >"$W_LIVE"
printf '%s\n' '{"b":1,"a":2}' >"$T_LIVE"

echo "== 全対象と target 指定 =="

rm -f "$W_REPO" "$T_REPO"
out=$(run pull)
rc=$?
check "target 省略で全部走る" "0" "$rc"
check "wslconfig が同期される" "yes" "$([ -f "$W_REPO" ] && echo yes || echo no)"
check "terminal が同期される" "yes" "$([ -f "$T_REPO" ] && echo yes || echo no)"
check "両方の結果を出す" "yes" \
  "$(has 'wslconfig' "$out" >/dev/null && has 'terminal' "$out")"

# INI は素通し（コメントが消えない）
check ".wslconfig のコメントが残る" "yes" "$(grep -q '実測値' "$W_REPO" && echo yes || echo no)"
# JSON は正規化される
check "terminal の JSON が正規化される" "yes" \
  "$(head -2 "$T_REPO" | tail -1 | grep -q '"a": 2' && echo yes || echo no)"

rm -f "$W_REPO"
out=$(run pull wslconfig)
rc=$?
check "target 指定で1つだけ走る" "0" "$rc"
check "指定した方は同期される" "yes" "$([ -f "$W_REPO" ] && echo yes || echo no)"
check "指定しなかった方は出力に出ない" "no" "$(has 'terminal' "$out")"

out=$(run status terminal)
check "status も target を取る" "yes" "$(has 'terminal' "$out")"

echo "== エラーの転送 =="

out=$(run pull nope)
rc=$?
check "不明な target は非0で返す" "1" "$rc"
check "指定できる値を出す" "yes" "$(has 'wslconfig' "$out")"

out=$(run pull --frobnicate)
rc=$?
check "不明なオプションは非0で返す" "1" "$rc"
check "何が不正だったか出す" "yes" "$(has 'frobnicate' "$out")"

# 壊れた JSON は反対側へ伝播させない
printf '%s\n' '{broken' >"$T_LIVE"
out=$(run pull terminal)
rc=$?
check "壊れた JSON の pull は非0" "1" "$rc"
check "JSON でないと伝える" "yes" "$(has '正しいJSONではありません' "$out")"

echo "== 1つの失敗で残りを止めない =="

# terminal は壊れたまま、wslconfig は正常 -> 全体は非0だが wslconfig は同期される
rm -f "$W_REPO"
out=$(run pull)
rc=$?
check "全体は非0で返す" "1" "$rc"
check "正常な方は同期される" "yes" "$([ -f "$W_REPO" ] && echo yes || echo no)"

echo "== dotctl の解決 =="

printf '%s\n' '{"a":1}' >"$T_LIVE"
mkdir -p "$FAKE_HOME/.local/bin"
printf '#!/bin/bash\necho HOME_BIN_USED\n' >"$FAKE_HOME/.local/bin/dotctl"
chmod +x "$FAKE_HOME/.local/bin/dotctl"
out=$(run status 2>&1)
check "\$HOME/.local/bin の dotctl を優先する" "yes" "$(has 'HOME_BIN_USED' "$out")"
rm -rf "$FAKE_HOME/.local"

out=$(env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" bash "$TARGET" status 2>&1)
rc=$?
check "dotctl が無ければ非0で返す" "1" "$rc"
check "ビルド方法を案内する" "yes" "$(has 'setup-dotctl.sh' "$out")"

echo
echo "結果: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
