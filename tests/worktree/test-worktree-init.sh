#!/bin/bash
# worktree-init.sh（互換 wrapper）の契約を検査する。
#
# **実装の振る舞いは Go 側が持つ**（internal/worktree の unit test と
# integration test）。ここは wrapper が引数・終了コード・出力を素通しすることと、
# dotctl の解決規則だけを見る。
#
# wrapper は $HOME/.local/bin/dotctl を優先するので、HOME を差し替えて
# hermetic にする（利用者の端末に入っている dotctl の版で結果が変わらないように）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
TARGET="$SCRIPTS_DIR/worktree-init.sh"

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

run_wrapper() {
  env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" bash "$TARGET" "$@" 2>&1
}

echo "== 引数と終了コードの転送 =="

# 実 worktree を作って通常経路を1本通す（wrapper が引数を落としていないこと）
REPO="$TEST_DIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
printf '.env\n' >"$REPO/.gitignore"
echo x >"$REPO/README"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init
echo 'SECRET=1' >"$REPO/.env"
WT="$TEST_DIR/wt"
git -C "$REPO" worktree add -q -b feat "$WT" >/dev/null 2>&1

out=$(run_wrapper --dry-run "$WT")
rc=$?
check "worktree パスを引数で渡せる" "0" "$rc"
check "--dry-run が伝わる" "yes" "$(has '\[dry-run\] copy: .env' "$out")"
check "dry-run では実際にコピーしない" "no" "$([ -e "$WT/.env" ] && echo yes || echo no)"

out=$(run_wrapper "$WT")
rc=$?
check "引数なしモードで成功する" "0" "$rc"
check "実際にコピーされる" "yes" "$([ -e "$WT/.env" ] && echo yes || echo no)"

# メイン worktree では失敗する（終了コードの転送）
out=$(run_wrapper "$REPO")
rc=$?
check "メイン worktree では非0で返す" "1" "$rc"
check "理由を伝える" "yes" "$(has 'メインworktree' "$out")"

# 非 git ディレクトリ
out=$(run_wrapper "$TEST_DIR")
rc=$?
check "非 git では非0で返す" "1" "$rc"

echo "== オプションの扱い =="

out=$(run_wrapper --frobnicate 2>&1)
rc=$?
check "知らないオプションは非0で返す" "1" "$rc"
check "何が不正だったか出す" "yes" "$(has 'frobnicate' "$out")"

out=$(run_wrapper --help 2>&1)
rc=$?
check "--help は 0 で返す" "0" "$rc"
check "--help に --dry-run が出る" "yes" "$(has -- '--dry-run' "$out")"

echo "== dotctl の解決 =="

mkdir -p "$FAKE_HOME/.local/bin"
printf '#!/bin/bash\necho HOME_BIN_USED\n' >"$FAKE_HOME/.local/bin/dotctl"
chmod +x "$FAKE_HOME/.local/bin/dotctl"
out=$(run_wrapper 2>&1)
check "\$HOME/.local/bin の dotctl を優先する" "yes" "$(has 'HOME_BIN_USED' "$out")"
rm -rf "$FAKE_HOME/.local"

out=$(env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" bash "$TARGET" 2>&1)
rc=$?
check "dotctl が無ければ非0で返す" "1" "$rc"
check "ビルド方法を案内する" "yes" "$(has 'setup-dotctl.sh' "$out")"

echo
echo "結果: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
