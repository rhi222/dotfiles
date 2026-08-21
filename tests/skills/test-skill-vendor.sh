#!/bin/bash
# skill-vendor.sh（互換 wrapper）の契約を検査する。
#
# **取込・更新・点検の振る舞いは Go 側が持つ**（internal/skill の
# TestVendor* / TestPreflight* / TestCheckLiveDirs*）。preflight の門前払い、
# live-dir の点検、update の差分表示と承認、.vendor.json の内容はすべてそちら。
#
# ここは wrapper の転送と、**環境変数の差し替え口が生きていること**を見る。
# 差し替え口が壊れると、テストが実 ~/.claude を触りに行く。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
TARGET="$SCRIPTS_DIR/skill-vendor.sh"

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

# **ネットワークに出ない。** ローカルの bare リポジトリを origin にする
WORK="$TEST_DIR/work"
mkdir -p "$WORK/skills/demo"
printf '# demo skill\n本文\n' >"$WORK/skills/demo/SKILL.md"
printf 'MIT License\n' >"$WORK/LICENSE"
git -C "$WORK" init -q
git -C "$WORK" config user.email test@example.com
git -C "$WORK" config user.name test
git -C "$WORK" add -A
git -C "$WORK" commit -qm init
ORIGIN="$TEST_DIR/origin.git"
git clone --quiet --bare "$WORK" "$ORIGIN"

VENDOR="$TEST_DIR/vendor"
CACHE="$TEST_DIR/cache"
SELF="$TEST_DIR/self"

run() {
  env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" \
    SKILL_VENDOR_DIR="$VENDOR" SKILL_VENDOR_CACHE="$CACHE" \
    SKILL_VENDOR_SELF_SKILLS="$SELF" \
    SKILL_VENDOR_YES=1 SKILL_VENDOR_DATE=2026-01-02 \
    bash "$TARGET" "$@" 2>&1
}

echo "== 環境変数の差し替え口と引数の転送 =="

out=$(run list)
rc=$?
check "取込前の list は 0 で返す" "0" "$rc"
check "取込先が空だと伝える" "yes" "$(has 'vendored skill はありません' "$out")"

out=$(run add "$ORIGIN" skills/demo)
rc=$?
check "add が成功する" "0" "$rc"
check "差し替えた取込先に入る" "yes" "$([ -f "$VENDOR/demo/SKILL.md" ] && echo yes || echo no)"
check "SKILL_VENDOR_YES が伝わる" "yes" "$(has '自動承認' "$out")"
check "次の手を案内する" "yes" "$(has 'dotfilesLink.sh' "$out")"

out=$(run list)
check "list に出る" "yes" "$(has 'demo' "$out")"
check "SKILL_VENDOR_DATE が伝わる" "yes" "$(has '2026-01-02' "$out")"
check "ライセンスを判定して出す" "yes" "$(has 'MIT' "$out")"

out=$(run status --no-network)
rc=$?
check "status は 0 で返す" "0" "$rc"
check "OK を出す" "yes" "$(has '\[OK\] demo' "$out")"

out=$(run update demo)
rc=$?
check "変更が無い update は 0 で返す" "0" "$rc"
check "変更なしと伝える" "yes" "$(has '変更なし' "$out")"

echo "== エラーの転送 =="

out=$(run update nope)
rc=$?
check "未登録の update は非0で返す" "1" "$rc"
check "見つからないと伝える" "yes" "$(has '見つかりません' "$out")"

out=$(run add justaword sub)
rc=$?
check "owner/repo でない spec は非0で返す" "1" "$rc"

out=$(run)
rc=$?
check "サブコマンド無しは 2 で返す" "2" "$rc"

out=$(run frobnicate)
rc=$?
check "知らないサブコマンドは 2 で返す" "2" "$rc"

echo "== preflight が wrapper 経由でも効く =="

# 自作 skill と名前が衝突する状態を作る
mkdir -p "$SELF/demo2"
out=$(run add "$ORIGIN" skills/demo demo2)
rc=$?
check "名前衝突は非0で返す" "1" "$rc"
check "衝突を伝える" "yes" "$(has '名前が衝突' "$out")"

echo "== dotctl の解決 =="

mkdir -p "$FAKE_HOME/.local/bin"
printf '#!/bin/bash\necho HOME_BIN_USED\n' >"$FAKE_HOME/.local/bin/dotctl"
chmod +x "$FAKE_HOME/.local/bin/dotctl"
out=$(run list)
check "\$HOME/.local/bin の dotctl を優先する" "yes" "$(has 'HOME_BIN_USED' "$out")"
rm -rf "$FAKE_HOME/.local"

out=$(env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" bash "$TARGET" list 2>&1)
rc=$?
check "dotctl が無ければ非0で返す" "1" "$rc"
check "ビルド方法を案内する" "yes" "$(has 'setup-dotctl.sh' "$out")"

echo
echo "結果: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
