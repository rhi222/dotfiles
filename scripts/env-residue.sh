#!/bin/bash
# env-residue.sh — dotctl doctor residue への互換 wrapper。
#
#   bash scripts/env-residue.sh
#
# 実装は Go 側（internal/doctor）にある。**この入口を残しているのは AGENTS.md と
# docs/migration.md が移行時の診断入口として案内しているため。**
#
# **見つかっても exit 0 する。** 残骸があること自体は壊れている状態ではなく、
# 放置すると事故になりうる状態。終了コードは診断を実行できたかどうかに使い、
# 残骸の有無は出力で伝える。
#
# 件数は機械可読サマリ行（env-residue: FOUND=N）から取る。
set -uo pipefail

DOTCTL="$HOME/.local/bin/dotctl"
[ -x "$DOTCTL" ] || DOTCTL="$(command -v dotctl 2>/dev/null || true)"

if [ -z "$DOTCTL" ]; then
  echo "env-residue: dotctl が見つからない。ビルドする: bash scripts/setup-dotctl.sh" >&2
  exit 1
fi

exec "$DOTCTL" doctor residue "$@"
