#!/bin/bash
# sync-claude-settings.sh（互換 wrapper）の契約を検査する。
#
# **実装の振る舞いは Go 側が持つ**（internal/settings の unit test）。
# 正規化が jq -S と一致すること・マスクとマージ・push の安全弁・権限の保持は
# すべてそちらにある。ここは wrapper が引数・終了コード・出力を素通しすること、
# そして環境変数の差し替え口が生きていることだけを見る。
#
# wrapper は $HOME/.local/bin/dotctl を優先するので HOME を差し替えて hermetic にする。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
TARGET="$SCRIPTS_DIR/settings/sync-claude.sh"

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

LIVE="$TEST_DIR/live.json"
REPO="$TEST_DIR/repo.json"
DICT="$TEST_DIR/dict.txt"

run() {
  env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" \
    CLAUDE_SETTINGS_LIVE="$LIVE" CLAUDE_SETTINGS_REPO="$REPO" SECRET_PATTERNS="$DICT" \
    bash "$TARGET" "$@" 2>&1
}

echo "== 環境変数の差し替え口と引数の転送 =="

printf '%s\n' '{"theme":"dark","b":1}' >"$LIVE"
rm -f "$REPO"
out=$(run pull)
rc=$?
check "pull が成功する" "0" "$rc"
check "リポジトリ側に書かれる" "yes" "$([ -f "$REPO" ] && echo yes || echo no)"
check "正規化されて入る（キー順が安定）" "yes" \
  "$(head -2 "$REPO" | tail -1 | grep -q '"b": 1' && echo yes || echo no)"

out=$(run pull)
check "2回目は変更なしと言う" "yes" "$(has '変更なし' "$out")"

printf '%s\n' '{"theme":"light","b":1}' >"$LIVE"
out=$(run pull --dry-run)
rc=$?
check "--dry-run が伝わる" "0" "$rc"
check "書き込まないと伝える" "yes" "$(has -- '--dry-run のため書き込みません' "$out")"
check "dry-run では書き換えない" "yes" "$(grep -q '"theme": "dark"' "$REPO" && echo yes || echo no)"

out=$(run status)
rc=$?
check "status は差分ありでも 0 で返す" "0" "$rc"
check "差分を報告する" "yes" "$(has '差分あり' "$out")"

echo "== push の安全弁（終了コードの転送） =="

out=$(run push)
rc=$?
check "差分ありの push は非0で返す" "1" "$rc"
check "pull を案内する" "yes" "$(has 'pull' "$out")"
check "実ファイルを書き換えない" "yes" "$(grep -q 'light' "$LIVE" && echo yes || echo no)"

out=$(run push --force)
rc=$?
check "--force が伝わる" "0" "$rc"
check "上書きしたと伝える" "yes" "$(has '上書き' "$out")"

echo "== 機密のマスク（辞書の差し替え口） =="

printf 'example-corp\n' >"$DICT"
printf '%s\n' '{"enabledPlugins":{"p@example-corp":true,"q@anthropics":true}}' >"$LIVE"
rm -f "$REPO"
run pull >/dev/null
check "機密はリポジトリに入らない" "no" "$(has 'example-corp' "$(cat "$REPO")")"
check "公開分は入る" "yes" "$(has 'q@anthropics' "$(cat "$REPO")")"

echo "== 壊れた入力 =="

printf '%s\n' '{broken' >"$LIVE"
out=$(run pull)
rc=$?
check "壊れた実ファイルの pull は非0" "1" "$rc"
check "JSON でないと伝える" "yes" "$(has '正しいJSONではありません' "$out")"

echo "== オプションと dotctl の解決 =="

out=$(run 2>&1)
rc=$?
check "サブコマンド無しは非0で返す" "2" "$rc"

mkdir -p "$FAKE_HOME/.local/bin"
printf '#!/bin/bash\necho HOME_BIN_USED\n' >"$FAKE_HOME/.local/bin/dotctl"
chmod +x "$FAKE_HOME/.local/bin/dotctl"
out=$(run status 2>&1)
check "\$HOME/.local/bin の dotctl を優先する" "yes" "$(has 'HOME_BIN_USED' "$out")"
rm -rf "$FAKE_HOME/.local"

out=$(env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" bash "$TARGET" status 2>&1)
rc=$?
check "dotctl が無ければ非0で返す" "1" "$rc"
check "ビルド方法を案内する" "yes" "$(has 'setup/dotctl.sh' "$out")"

echo
echo "結果: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
