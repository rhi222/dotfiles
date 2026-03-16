#!/bin/bash
set -euo pipefail

# AutoHotKey用の設定ファイルをwsl2→windowsにデプロイ
# Usage: bash .config/AutoHotkey/deploy-ahk-script.sh [--dry-run]

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/scripts"

WIN_USER="$(cmd.exe /c echo %USERNAME% 2>/dev/null | tr -d '\r\n')"
if [ -z "$WIN_USER" ]; then
  echo "[FAIL] Windowsユーザー名を取得できませんでした" >&2
  exit 1
fi

DEST_DIR="/mnt/c/Users/$WIN_USER/Documents/AutoHotkey"

if [ ! -d "$DEST_DIR" ]; then
  if $DRY_RUN; then
    echo "[DRY-RUN] mkdir -p $DEST_DIR"
  else
    echo "[INFO] $DEST_DIR が存在しないため作成します"
    mkdir -p "$DEST_DIR"
  fi
fi

for file in "$SRC_DIR"/*; do
  [ -f "$file" ] || continue
  if $DRY_RUN; then
    echo "[DRY-RUN] cp $(basename "$file") -> $DEST_DIR/"
  else
    cp "$file" "$DEST_DIR/"
    echo "[OK] $(basename "$file") -> $DEST_DIR/"
  fi
done
