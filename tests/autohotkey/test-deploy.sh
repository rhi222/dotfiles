#!/bin/bash
# deploy-ahk-script.sh は WSL 側の .ahk を Windows の Documents\AutoHotkey へ配る。
#
# text-snippet.ahk が組み立てる \\wsl$ パスは distro 名と Linux ユーザー名に依存し、
# これらは端末ごとに変わる（PC移行で Ubuntu -> Ubuntu-24.04 になり、
# SNIPPET_ROOT が丸ごと存在しないパスになって Passwords が消えた実績がある）。
# リポジトリのソースには既定値だけを置き、配備時に実行環境の値を埋め込む。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET="$REPO_ROOT/.config/AutoHotkey/deploy-ahk-script.sh"
SRC="$REPO_ROOT/.config/AutoHotkey/scripts/text-snippet.ahk"

PASS=0
FAIL=0
TOTAL=0

check() {
  local name="$1" ok="$2"
  TOTAL=$((TOTAL + 1))
  if [[ "$ok" == "yes" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    check "$name" yes
  else
    check "$name" no
    echo "        [$needle] を含むべき"
    echo "        実際: [$haystack]"
  fi
}

DEST="$(mktemp -d)"
trap 'rm -rf "$DEST"' EXIT

echo "=== 実行環境の distro 名とユーザー名を埋め込む ==="
out=$(AHK_DEST_DIR="$DEST/deploy" WSL_DISTRO_NAME="Ubuntu-24.04" USER="tester" \
  bash "$TARGET" 2>&1)
deployed=$(cat "$DEST/deploy/text-snippet.ahk" 2>/dev/null)
assert_contains "WSL_DISTRO に distro 名が入る" "$deployed" 'WSL_DISTRO := "Ubuntu-24.04"'
assert_contains "WSL_USER に Linux ユーザー名が入る" "$deployed" 'WSL_USER   := "tester"'
assert_contains "配備ログを出す" "$out" "text-snippet.ahk"

echo "=== リポジトリ側のソースは書き換えない ==="
if grep -q 'WSL_DISTRO := "Ubuntu-24.04"' "$SRC"; then
  check "ソースに端末固有値を書き戻さない" no
else
  check "ソースに端末固有値を書き戻さない" yes
fi

echo "=== cmd.exe が無い環境でも AHK_DEST_DIR 指定なら動く ==="
out2=$(AHK_DEST_DIR="$DEST/nopath" WSL_DISTRO_NAME="Ubuntu-24.04" USER="tester" \
  env PATH="/usr/bin:/bin" bash "$TARGET" 2>&1)
status2=$?
if [[ $status2 -eq 0 && -f "$DEST/nopath/text-snippet.ahk" ]]; then
  check "Windows ユーザー名の取得を試みない" yes
else
  check "Windows ユーザー名の取得を試みない" no
  echo "        status=$status2 out=[$out2]"
fi

echo "=== --dry-run は配備しない ==="
out3=$(AHK_DEST_DIR="$DEST/dry" WSL_DISTRO_NAME="Ubuntu-24.04" USER="tester" \
  bash "$TARGET" --dry-run 2>&1)
if [[ ! -e "$DEST/dry" ]]; then
  check "ファイルを作らない" yes
else
  check "ファイルを作らない" no
fi
assert_contains "DRY-RUN と表示する" "$out3" "[DRY-RUN]"

echo ""
echo "================================"
echo "合計: $TOTAL / PASS: $PASS / FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
