#!/bin/bash
# env-residue.sh（互換 wrapper）の契約を検査する。
#
# **検出の中身は Go 側が持つ**（internal/doctor の TestResidue*）。fisher の
# 判定を名前の規約ではなく fisher 自身の一覧で行うこと、宣言が読めないときに
# skill の判定を諦めること、vendored が実ディレクトリなのを見つけることは
# すべてそちら。
#
# ここは wrapper の転送と、**見つかっても exit 0 であること**を見る。
# 終了コードは残骸の有無ではなく、診断を実行できたかどうかを表す。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
TARGET="$SCRIPTS_DIR/env-residue.sh"

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
FAKE_REPO="$TEST_DIR/repo"
mkdir -p "$FAKE_HOME" "$FAKE_REPO/scripts"
printf '# 宣言\n' >"$FAKE_REPO/scripts/claude-skills.txt"

if ! (cd "$REPO_ROOT" && go build -o "$TEST_DIR/dotctl" ./cmd/dotctl) 2>"$TEST_DIR/build.err"; then
  echo "ERROR: dotctl のビルドに失敗"
  cat "$TEST_DIR/build.err"
  exit 1
fi

# env-residue.sh は引数を取らない
run() {
  env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" ENV_RESIDUE_REPO="$FAKE_REPO" \
    bash "$TARGET" 2>&1
}

echo "== 環境変数の差し替え口と機械可読サマリ =="

out=$(run)
rc=$?
check "綺麗な環境で 0 で返す" "0" "$rc"
check "残骸なしと伝える" "yes" "$(has '残骸は見つかりませんでした' "$out")"
check "機械可読サマリを出す" "yes" "$(has 'env-residue: FOUND=0' "$out")"

# 残骸を1つ作る
mkdir -p "$FAKE_HOME/.fzf"
out=$(run)
rc=$?
# **見つかっても 0。** 終了コードは診断自体の成否を表す
check "残骸があっても 0 で返す" "0" "$rc"
# 報告文の中の ~ は表示用のリテラル（展開させない）
# shellcheck disable=SC2088
check "残骸を報告する" "yes" "$(has '~/.fzf/ が残っています' "$out")"
check "件数をサマリに出す" "yes" "$(has 'env-residue: FOUND=1' "$out")"
check "撤去手順を出す" "yes" "$(has 'rm -rf ~/.fzf' "$out")"

echo "== 機械可読サマリから件数を読めるか =="

count=$(run | sed -nE 's/^env-residue: FOUND=([0-9]+)$/\1/p')
check "サマリ行から件数を取れる" "1" "$count"

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
