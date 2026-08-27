#!/bin/bash
# wsl-cleanup.sh — dotctl wsl cleanup への互換 wrapper。
#
#   bash scripts/wsl/cleanup.sh            # dry-run（既定）
#   bash scripts/wsl/cleanup.sh --execute  # 実削除
#
# 実装は Go 側（internal/wsl）にある。**この入口を残しているのは AGENTS.md が
# このパスで案内しているため。**
#
# .cargo / .rustup / ~/go / mise / nvim / claude など開発環境の本体は触らない。
# ext4.vhdx の圧縮は Windows 側で手動（実行後に手順を案内する）。
set -uo pipefail

DOTCTL="$HOME/.local/bin/dotctl"
[ -x "$DOTCTL" ] || DOTCTL="$(command -v dotctl 2>/dev/null || true)"

if [ -z "$DOTCTL" ]; then
  echo "wsl-cleanup: dotctl が見つからない。ビルドする: bash scripts/setup/dotctl.sh" >&2
  exit 1
fi

exec "$DOTCTL" wsl cleanup "$@"
