#!/bin/bash
# migration-check.sh（互換 wrapper）の契約を検査する。
#
# **判定の中身は Go 側が持つ**（internal/doctor の TestRepoState* /
# TestInspectRepo* / TestCheckMigration*）。remote なし・未 push・stash・
# dirty・worktree の判定と行の体裁はそちら。
#
# ここは wrapper の転送と、**終了コードが移行判断に使えること**を見る。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
TARGET="$SCRIPTS_DIR/migration-check.sh"

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
mkdir -p "$FAKE_HOME"

if ! (cd "$REPO_ROOT" && go build -o "$TEST_DIR/dotctl" ./cmd/dotctl) 2>"$TEST_DIR/build.err"; then
  echo "ERROR: dotctl のビルドに失敗"
  cat "$TEST_DIR/build.err"
  exit 1
fi

run() {
  env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" bash "$TARGET" "$@" 2>&1
}

# きれいなリポジトリ（remote あり・差分なし）
CLEAN="$TEST_DIR/clean"
mkdir -p "$CLEAN"
git -C "$CLEAN" init -q
git -C "$CLEAN" config user.email test@example.com
git -C "$CLEAN" config user.name test
git -C "$CLEAN" remote add origin https://example.invalid/r.git

# 作業状態が残るリポジトリ（remote なし）
DIRTY="$TEST_DIR/dirty"
mkdir -p "$DIRTY"
git -C "$DIRTY" init -q
git -C "$DIRTY" config user.email test@example.com
git -C "$DIRTY" config user.name test

echo "== 引数と終了コードの転送 =="

out=$(run "$CLEAN")
rc=$?
check "きれいなら 0 で返す" "0" "$rc"
check "集計を出す" "yes" "$(has '0/1 リポジトリ' "$out")"

out=$(run "$DIRTY")
rc=$?
check "作業状態が残れば 1 で返す" "1" "$rc"
check "remote なしを報告する" "yes" "$(has 'remote:なし' "$out")"
check "対象パスを出す" "yes" "$(has "$DIRTY" "$out")"

out=$(run "$CLEAN" "$DIRTY")
rc=$?
check "複数ディレクトリを渡せる" "1" "$rc"
check "件数を集計する" "yes" "$(has '1/2 リポジトリ' "$out")"

out=$(run "$TEST_DIR")
rc=$?
check "git でないディレクトリは数えない" "0" "$rc"
check "0/0 と出す" "yes" "$(has '0/0 リポジトリ' "$out")"

echo "== dotctl の解決 =="

mkdir -p "$FAKE_HOME/.local/bin"
printf '#!/bin/bash\necho HOME_BIN_USED\n' >"$FAKE_HOME/.local/bin/dotctl"
chmod +x "$FAKE_HOME/.local/bin/dotctl"
out=$(run "$CLEAN")
check "\$HOME/.local/bin の dotctl を優先する" "yes" "$(has 'HOME_BIN_USED' "$out")"
rm -rf "$FAKE_HOME/.local"

out=$(env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" bash "$TARGET" "$CLEAN" 2>&1)
rc=$?
check "dotctl が無ければ非0で返す" "1" "$rc"
check "ビルド方法を案内する" "yes" "$(has 'setup-dotctl.sh' "$out")"

echo
echo "結果: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
