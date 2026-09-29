#!/bin/bash
# nodemodules/cleanup.sh — dotctl node-modules cleanup への wrapper。
#
#   bash scripts/nodemodules/cleanup.sh                # dry-run（既定）
#   bash scripts/nodemodules/cleanup.sh --execute      # 実削除
#   bash scripts/nodemodules/cleanup.sh --days 180     # 閾値を変える
#
# 実装は Go 側（internal/nodemodules）にある。走査ルートは NODE_MODULES_CLEANUP_ROOTS
# （既定 /data/git-repos）。
set -uo pipefail

DOTCTL="$HOME/.local/bin/dotctl"
[ -x "$DOTCTL" ] || DOTCTL="$(command -v dotctl 2>/dev/null || true)"

if [ -z "$DOTCTL" ]; then
  echo "nodemodules-cleanup: dotctl が見つからない。ビルドする: bash scripts/setup/dotctl.sh" >&2
  exit 1
fi

exec "$DOTCTL" node-modules cleanup "$@"
