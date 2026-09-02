#!/bin/bash
set -euo pipefail

# AutoHotKey用の設定ファイルをwsl2→windowsにデプロイ
# Usage: bash .config/AutoHotkey/deploy-ahk-script.sh [--dry-run]
#
# text-snippet.ahk が組み立てる \\wsl$ パスは distro 名とLinuxユーザー名に依存する。
# これらは端末ごとに変わるため、リポジトリには既定値だけを置き、配備時に実行環境の
# 値へ差し替える。ソース側は書き換えない。

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/scripts"

if [ -n "${AHK_DEST_DIR:-}" ]; then
  DEST_DIR="$AHK_DEST_DIR"
else
  WIN_USER="$(cmd.exe /c echo %USERNAME% 2>/dev/null | tr -d '\r\n')"
  if [ -z "$WIN_USER" ]; then
    echo "[FAIL] Windowsユーザー名を取得できませんでした" >&2
    exit 1
  fi
  DEST_DIR="/mnt/c/Users/$WIN_USER/Documents/AutoHotkey"
fi

WSL_DISTRO="${WSL_DISTRO_NAME:-Ubuntu}"
WSL_USER="${USER:-$(id -un)}"

if [ ! -d "$DEST_DIR" ]; then
  if $DRY_RUN; then
    echo "[DRY-RUN] mkdir -p $DEST_DIR"
  else
    echo "[INFO] $DEST_DIR が存在しないため作成します"
    mkdir -p "$DEST_DIR"
  fi
fi

# 端末固有値の差し替え。既定値のままの行だけを対象にする（= 冪等）
localize() {
  sed -i \
    -e "s|^WSL_DISTRO := \".*\"|WSL_DISTRO := \"$WSL_DISTRO\"|" \
    -e "s|^WSL_USER   := \".*\"|WSL_USER   := \"$WSL_USER\"|" \
    "$1"
}

for file in "$SRC_DIR"/*; do
  [ -f "$file" ] || continue
  name="$(basename "$file")"
  if $DRY_RUN; then
    echo "[DRY-RUN] cp $name -> $DEST_DIR/"
    [ "$name" = "text-snippet.ahk" ] &&
      echo "[DRY-RUN]   WSL_DISTRO=$WSL_DISTRO WSL_USER=$WSL_USER を埋め込み"
  else
    cp "$file" "$DEST_DIR/"
    if [ "$name" = "text-snippet.ahk" ]; then
      localize "$DEST_DIR/$name"
      echo "[OK] $name -> $DEST_DIR/ (WSL_DISTRO=$WSL_DISTRO WSL_USER=$WSL_USER)"
    else
      echo "[OK] $name -> $DEST_DIR/"
    fi
  fi
done
