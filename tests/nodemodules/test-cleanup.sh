#!/bin/bash
# nodemodules/cleanup.sh（dotctl node-modules cleanup への wrapper）の契約を検査する。
#
# **判定の分岐は Go 側が持つ**（internal/nodemodules の unit test）。ここは
# wrapper の転送、dry-run が既定であること、実 git の HEAD 時刻で判定できることを見る。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
TARGET="$SCRIPTS_DIR/nodemodules/cleanup.sh"

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
present() { [ -e "$1" ] && echo yes || echo no; }

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
FAKE_HOME="$TEST_DIR/home"
ROOT="$TEST_DIR/repos"
mkdir -p "$FAKE_HOME"

# make_repo <dir> <commit日時>: 指定日時の commit を1つ持つ repo と node_modules を作る
make_repo() {
  local dir="$1" date="$2"
  mkdir -p "$dir/node_modules/pkg"
  git -C "$dir" init -q
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "$dir" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  touch -d "$date" "$dir/node_modules/pkg" "$dir/node_modules"
}
make_repo "$ROOT/old" "2020-01-01T00:00:00"
make_repo "$ROOT/new" "$(date -d '-1 day' +%Y-%m-%dT%H:%M:%S)"

if ! (cd "$REPO_ROOT" && go build -o "$TEST_DIR/dotctl" ./cmd/dotctl) 2>"$TEST_DIR/build.err"; then
  echo "ERROR: dotctl のビルドに失敗"
  cat "$TEST_DIR/build.err"
  exit 1
fi

run() {
  env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" NODE_MODULES_CLEANUP_ROOTS="$ROOT" \
    bash "$TARGET" "$@" 2>&1
}

echo "== dry-run が既定 =="

out=$(run)
rc=$?
check "引数なしで 0 で返す" "0" "$rc"
check "DRY-RUN と表示する" "yes" "$(has 'DRY-RUN' "$out")"
check "古い repo を候補に出す" "yes" "$(has "$ROOT/old/node_modules" "$out")"
check "新しい repo を候補に出さない" "no" "$(has "$ROOT/new/node_modules" "$out")"
check "契約行で件数を出す" "yes" "$(has '^node-modules-cleanup: CANDIDATES=1 ' "$out")"
check "既定では削除しない" "yes" "$(present "$ROOT/old/node_modules")"
check "実行方法を案内する" "yes" "$(has -- '--execute' "$out")"

echo "== --days の転送 =="

out=$(run --days 100000)
check "--days で閾値を変えられる" "yes" "$(has 'CANDIDATES=0' "$out")"

echo "== --execute の転送 =="

out=$(run --execute)
rc=$?
check "--execute が伝わる" "0" "$rc"
check "EXECUTE と表示する" "yes" "$(has 'EXECUTE' "$out")"
check "古い node_modules を消す" "no" "$(present "$ROOT/old/node_modules")"
check "新しい node_modules は残す" "yes" "$(present "$ROOT/new/node_modules")"
check "repo 本体は残す" "yes" "$(present "$ROOT/old/.git")"

echo "== オプションの扱い =="

out=$(run --frobnicate)
rc=$?
check "知らないオプションは非0で返す" "1" "$rc"
check "何が不正だったか出す" "yes" "$(has 'frobnicate' "$out")"

out=$(run --days abc)
rc=$?
check "--days が数でなければ非0で返す" "1" "$rc"

out=$(run --help)
rc=$?
check "--help は 0 で返す" "0" "$rc"
check "--help に --execute が出る" "yes" "$(has -- '--execute' "$out")"

echo "== dotctl の解決 =="

out=$(env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" bash "$TARGET" 2>&1)
rc=$?
check "dotctl が無ければ非0で返す" "1" "$rc"
check "ビルド方法を案内する" "yes" "$(has 'setup/dotctl.sh' "$out")"

echo
echo "結果: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
