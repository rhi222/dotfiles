#!/bin/bash
# migration-check.sh — dotctl doctor migration への互換 wrapper。
#
#   bash scripts/migration-check.sh              # ghq の全リポジトリ + ホーム直下
#   bash scripts/migration-check.sh <dir>...     # 指定ディレクトリだけ
#
# 実装は Go 側（internal/doctor）にある。**この入口を残しているのは
# docs/migration.md がこのパスで案内しているため。**
#
# PC 移行は「再clone を基本とし、ローカル専用の状態が残るリポジトリだけ tar で
# 運ぶ」方針（docs/migration.md）で、その3グループ判定の入力を作る。
#
# 終了コード: 0 = 全リポジトリきれい / 1 = 作業状態が残るリポジトリあり
set -uo pipefail

DOTCTL="$HOME/.local/bin/dotctl"
[ -x "$DOTCTL" ] || DOTCTL="$(command -v dotctl 2>/dev/null || true)"

if [ -z "$DOTCTL" ]; then
  echo "migration-check: dotctl が見つからない。ビルドする: bash scripts/setup-dotctl.sh" >&2
  exit 1
fi

exec "$DOTCTL" doctor migration "$@"
