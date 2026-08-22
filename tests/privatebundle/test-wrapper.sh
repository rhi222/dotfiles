#!/bin/bash
# private-bundle.sh（互換 wrapper）の契約を検査する。
#
# **集約・運搬の振る舞いは Go 側が持つ**（internal/privatebundle の unit test と
# integration test）。分類の判定、追跡ファイルを巻き込まない ignore 判定、
# パーミッションのハードニング、zip -y で symlink を実体化しないことはそちら。
#
# ここは wrapper の転送と、**環境変数の差し替え口が生きていること**を見る。
# 差し替え口が壊れると、テストが実 $HOME の機密ファイルを動かしに行く。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
TARGET="$SCRIPTS_DIR/private-bundle.sh"

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
PRIVATE="$TEST_DIR/private"
mkdir -p "$FAKE_HOME/.claude" "$FAKE_REPO/.config/git"
printf 'ctx\n' >"$FAKE_HOME/.claude/local-context.md"
printf 'cfg\n' >"$FAKE_REPO/.config/git/config-local"
git -C "$FAKE_REPO" init -q
git -C "$FAKE_REPO" config user.email test@example.com
git -C "$FAKE_REPO" config user.name test

if ! (cd "$REPO_ROOT" && go build -o "$TEST_DIR/dotctl" ./cmd/dotctl) 2>"$TEST_DIR/build.err"; then
  echo "ERROR: dotctl のビルドに失敗"
  cat "$TEST_DIR/build.err"
  exit 1
fi

run() {
  env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" \
    DOTFILES_DIR="$FAKE_REPO" DOTFILES_PRIVATE_DIR="$PRIVATE" \
    PRIVATE_BUNDLE_ZIP_PASSWORD=testpass \
    bash "$TARGET" "$@" 2>&1
}

echo "== 環境変数の差し替え口と引数の転送 =="

out=$(run status)
rc=$?
check "集約先が無い status は 0 で返す" "0" "$rc"
check "雛形生成へのフォールバックを案内する" "yes" "$(has '雛形生成にフォールバック' "$out")"

out=$(run adopt)
rc=$?
check "adopt の既定は dry-run" "0" "$rc"
check "dry-run と伝える" "yes" "$(has 'dry-run です' "$out")"
check "dry-run では動かさない" "no" "$([ -d "$PRIVATE" ] && echo yes || echo no)"

out=$(run adopt --execute)
rc=$?
check "--execute が伝わる" "0" "$rc"
check "差し替えた集約先へ移す" "yes" \
  "$([ -f "$PRIVATE/home/.claude/local-context.md" ] && echo yes || echo no)"
check "元の場所は symlink になる" "yes" \
  "$([ -L "$FAKE_HOME/.claude/local-context.md" ] && echo yes || echo no)"
check "集約先を 700 に締める" "700" "$(stat -c '%a' "$PRIVATE")"

out=$(run status)
check "adopt 後はリンク済みに出る" "yes" "$(has 'リンク済み (2)' "$out")"

echo "== export / import =="

ZIP="$TEST_DIR/bundle.zip"
out=$(run export --out "$ZIP")
rc=$?
check "export が成功する" "0" "$rc"
check "zip を作る" "yes" "$([ -f "$ZIP" ] && echo yes || echo no)"
check "zip を 600 にする" "600" "$(stat -c '%a' "$ZIP")"

out=$(env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" \
  DOTFILES_PRIVATE_DIR="$TEST_DIR/restored" PRIVATE_BUNDLE_ZIP_PASSWORD=testpass \
  bash "$TARGET" import "$ZIP" 2>&1)
rc=$?
check "import が成功する" "0" "$rc"
check "復元される" "yes" \
  "$([ -f "$TEST_DIR/restored/home/.claude/local-context.md" ] && echo yes || echo no)"
check "次の手を案内する" "yes" "$(has 'dotfilesLink.sh' "$out")"

echo "== エラーの転送 =="

out=$(run import)
rc=$?
check "zip 指定なしは 1 で返す" "1" "$rc"

out=$(run adopt --bogus)
rc=$?
check "不明な引数は 2 で返す" "2" "$rc"

out=$(run frobnicate)
rc=$?
check "知らないサブコマンドは 2 で返す" "2" "$rc"

# 既存の集約先を --force なしで上書きしない
out=$(env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" \
  DOTFILES_PRIVATE_DIR="$TEST_DIR/restored" PRIVATE_BUNDLE_ZIP_PASSWORD=testpass \
  bash "$TARGET" import "$ZIP" 2>&1)
rc=$?
check "既存の集約先は --force なしで上書きしない" "1" "$rc"
check "--force を案内する" "yes" "$(has -- '--force' "$out")"

echo "== dotctl の解決 =="

mkdir -p "$FAKE_HOME/.local/bin"
printf '#!/bin/bash\necho HOME_BIN_USED\n' >"$FAKE_HOME/.local/bin/dotctl"
chmod +x "$FAKE_HOME/.local/bin/dotctl"
out=$(run status)
check "\$HOME/.local/bin の dotctl を優先する" "yes" "$(has 'HOME_BIN_USED' "$out")"
rm -rf "$FAKE_HOME/.local"

out=$(env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" bash "$TARGET" status 2>&1)
rc=$?
check "dotctl が無ければ非0で返す" "1" "$rc"
check "ビルド方法を案内する" "yes" "$(has 'setup-dotctl.sh' "$out")"

echo
echo "結果: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
