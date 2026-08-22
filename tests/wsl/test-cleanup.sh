#!/bin/bash
# wsl-cleanup.sh（互換 wrapper）の契約を検査する。
#
# **掃除の振る舞いは Go 側が持つ**（internal/wsl の unit test）。現行 pnpm store を
# 消さないこと、開発環境の本体（.cargo / .rustup / ~/go / mise / nvim / claude）を
# 触らないこと、ext4.vhdx の案内を出すことはすべてそちら。
#
# ここは wrapper の転送と、**dry-run が既定であること**を見る。既定が実削除に
# 転ぶと取り返しがつかない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
TARGET="$SCRIPTS_DIR/wsl-cleanup.sh"

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
FAKE_HOME="$TEST_DIR/home"
mkdir -p "$FAKE_HOME/.cache/puppeteer" "$FAKE_HOME/.cargo"
printf 'x\n' >"$FAKE_HOME/.cache/puppeteer/blob"
printf 'x\n' >"$FAKE_HOME/.cargo/keep"

if ! (cd "$REPO_ROOT" && go build -o "$TEST_DIR/dotctl" ./cmd/dotctl) 2>"$TEST_DIR/build.err"; then
  echo "ERROR: dotctl のビルドに失敗"
  cat "$TEST_DIR/build.err"
  exit 1
fi

run() {
  env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" bash "$TARGET" "$@" 2>&1
}

echo "== dry-run が既定 =="

out=$(run)
rc=$?
check "引数なしで 0 で返す" "0" "$rc"
check "DRY-RUN と表示する" "yes" "$(has 'DRY-RUN' "$out")"
check "削除しないと伝える" "yes" "$(has 'dry-run: 削除しません' "$out")"
check "既定では削除しない" "yes" "$([ -f "$FAKE_HOME/.cache/puppeteer/blob" ] && echo yes || echo no)"
check "実行方法を案内する" "yes" "$(has -- '--execute' "$out")"
check "vhdx の圧縮手順を出す" "yes" "$(has 'compact vdisk' "$out")"

echo "== --execute の転送 =="

out=$(run --execute)
rc=$?
check "--execute が伝わる" "0" "$rc"
check "EXECUTE と表示する" "yes" "$(has 'EXECUTE' "$out")"
check "対象を削除する" "no" "$([ -e "$FAKE_HOME/.cache/puppeteer" ] && echo yes || echo no)"
# **開発環境の本体は触らない**（wrapper 越しでも守られていること）
check "開発環境の本体は残る" "yes" "$([ -f "$FAKE_HOME/.cargo/keep" ] && echo yes || echo no)"

echo "== オプションの扱い =="

out=$(run --frobnicate)
rc=$?
check "知らないオプションは非0で返す" "1" "$rc"
check "何が不正だったか出す" "yes" "$(has 'frobnicate' "$out")"

out=$(run --help)
rc=$?
check "--help は 0 で返す" "0" "$rc"
check "--help に --execute が出る" "yes" "$(has -- '--execute' "$out")"

echo "== dotctl の解決 =="

mkdir -p "$FAKE_HOME/.local/bin"
printf '#!/bin/bash\necho HOME_BIN_USED\n' >"$FAKE_HOME/.local/bin/dotctl"
chmod +x "$FAKE_HOME/.local/bin/dotctl"
out=$(run)
check "\$HOME/.local/bin の dotctl を優先する" "yes" "$(has 'HOME_BIN_USED' "$out")"
rm -rf "$FAKE_HOME/.local"

out=$(env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" bash "$TARGET" 2>&1)
rc=$?
check "dotctl が無ければ非0で返す" "1" "$rc"
check "ビルド方法を案内する" "yes" "$(has 'setup-dotctl.sh' "$out")"

echo
echo "結果: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
