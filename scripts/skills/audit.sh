#!/bin/bash
# skill-audit.sh — dotctl skill audit への互換 wrapper。
#
#   bash scripts/skills/audit.sh [--quiet] <skill-dir>
#
# 実装は Go 側（internal/skill）にある。**この入口を残しているのは AGENTS.md と
# docs/agent-skills.md がこのパスで案内しているため。**
#
# 終了コードは HIGH が1件以上あれば 1、それ以外は 0。**取込の可否はここでは
# 決めない。** 平文で書かれた指示型の injection は正規表現では拾い切れないので、
# vendoring 側は audit が 0 でも人の承認を要求する。
set -uo pipefail

DOTCTL="$HOME/.local/bin/dotctl"
[ -x "$DOTCTL" ] || DOTCTL="$(command -v dotctl 2>/dev/null || true)"

if [ -z "$DOTCTL" ]; then
  echo "skill-audit: dotctl が見つからない。ビルドする: bash scripts/setup/dotctl.sh" >&2
  exit 1
fi

exec "$DOTCTL" skill audit "$@"
