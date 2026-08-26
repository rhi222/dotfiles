#!/bin/bash
# skill-vendor.sh — dotctl skill vendor への互換 wrapper。
#
#   bash scripts/skill-vendor.sh add <owner/repo|git-url> <sub-path> [name]
#   bash scripts/skill-vendor.sh update <name> [name...]
#   bash scripts/skill-vendor.sh status [--no-network]
#   bash scripts/skill-vendor.sh list
#
# 実装は Go 側（internal/skill）にある。**この入口を残しているのは AGENTS.md・
# docs/agent-skills.md・daily-update.sh がこのパスで呼んでいるため。**
#
# 信頼済み owner でない skill をここで取り込む理由（更新のレビュー面を git 差分に
# 一本化する）は docs/agent-skills.md。
set -uo pipefail

DOTCTL="$HOME/.local/bin/dotctl"
[ -x "$DOTCTL" ] || DOTCTL="$(command -v dotctl 2>/dev/null || true)"

if [ -z "$DOTCTL" ]; then
  echo "skill-vendor: dotctl が見つからない。ビルドする: bash scripts/setup-dotctl.sh" >&2
  exit 1
fi

exec "$DOTCTL" skill vendor "$@"
