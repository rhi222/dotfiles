#!/bin/bash
# dotfilesLink.sh の関数単体テスト。
# 実際にリンクを張る処理は呼ばず、source して個々の関数だけを検証する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../dotfilesLink.sh"

pass=0
fail=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "NG: $desc"
    fail=$((fail + 1))
  fi
}

# check は真を期待するので、否定はこちらを使う（! はコマンドではないため渡せない）
refute_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if grep -q -- "$needle" <<<"$haystack"; then
    echo "NG: $desc"
    fail=$((fail + 1))
  else
    echo "ok: $desc"
    pass=$((pass + 1))
  fi
}

if [[ ! -f "$SETUP" ]]; then
  echo "ERROR: $SETUP が存在しません"
  exit 1
fi

# shellcheck source=/dev/null  # 検査対象は実行時に決まる相対パス
source "$SETUP"
set +eo pipefail # スクリプト側の set -euo pipefail をテストシェルへ持ち込まない

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# source しただけで main が走っていないこと（走ると実際にリンクが張られてしまう）
check "関数だけが読み込まれ main は走らない" test "$(type -t warn_missing_local_git)" = function

# --- warn_missing_local_git ---
# .gitconfig が無条件 include するのは config-local だけ。config-work は
# config-local 側の includeIf から参照される任意ファイルなので、
# 不在でも警告してはいけない（毎回ノイズが出る）
mkdir -p "$tmp/dc/git"

out=$(DC="$tmp/dc" warn_missing_local_git 2>&1)
check "config-local が無ければ警告する" grep -q "config-local" <<<"$out"

: >"$tmp/dc/git/config-local"
out=$(DC="$tmp/dc" warn_missing_local_git 2>&1)
check "config-local があれば警告しない" test -z "$out"
refute_contains "config-work が無くても警告しない" "config-work" "$out"

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
