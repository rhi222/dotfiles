#!/bin/bash
# sync-windows-settings.sh — dotctl settings sync windows への互換 wrapper。
#
#   bash scripts/settings/sync-windows.sh status [target]
#   bash scripts/settings/sync-windows.sh pull   [target] [--dry-run]
#   bash scripts/settings/sync-windows.sh push   [target] [--force]
#
#   target を省略すると全部（wslconfig / terminal）。
#
# 実装は Go 側（internal/settings）にある。**この入口を残しているのは
# AGENTS.md と docs/bootstrap.md がこのパスで案内しているため。**
#
# symlink にできない理由（NTFS 上の実体 / Windows Terminal の自動追記）と、
# dotfilesLink.sh から呼ばない理由は AGENTS.md の「Windows 側設定の同期」節。
set -uo pipefail

DOTCTL="$HOME/.local/bin/dotctl"
[ -x "$DOTCTL" ] || DOTCTL="$(command -v dotctl 2>/dev/null || true)"

if [ -z "$DOTCTL" ]; then
  echo "sync-windows-settings: dotctl が見つからない。ビルドする: bash scripts/setup/dotctl.sh" >&2
  exit 1
fi

exec "$DOTCTL" settings sync windows "$@"
