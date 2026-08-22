#!/bin/bash
# private-bundle.sh — dotctl private-bundle への互換 wrapper。
#
#   bash scripts/private-bundle.sh adopt [--execute]   # 散らばった実体を集約先へ（旧環境で1回）
#   bash scripts/private-bundle.sh export [--out PATH] # パスワード付き zip に固める
#   bash scripts/private-bundle.sh import <zip> [--force]
#   bash scripts/private-bundle.sh status
#
# 実装は Go 側（internal/privatebundle）にある。**この入口を残しているのは AGENTS.md・
# docs/bootstrap.md・docs/migration.md がこのパスで案内しているため。**
#
# 集約先が実体で、各所へは dotfilesLink.sh が symlink を張る。移植対象の宣言は
# Go 側（internal/privatebundle の Entries）が持つ。
set -uo pipefail

DOTCTL="$HOME/.local/bin/dotctl"
[ -x "$DOTCTL" ] || DOTCTL="$(command -v dotctl 2>/dev/null || true)"

if [ -z "$DOTCTL" ]; then
  echo "private-bundle: dotctl が見つからない。ビルドする: bash scripts/setup-dotctl.sh" >&2
  exit 1
fi

exec "$DOTCTL" private-bundle "$@"
