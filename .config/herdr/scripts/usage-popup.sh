#!/bin/bash
# prefix+u の popup: agent usage の色付き詳細表示。任意のキーで閉じる。
set -uo pipefail

DOTCTL="${HERDR_USAGE_DOTCTL:-${HOME:-}/.local/bin/dotctl}"
if [ -x "$DOTCTL" ]; then
  "$DOTCTL" agent-usage detail --color
else
  printf '\033[1;33m%s\033[0m\n' "dotctl が見つからない。bash scripts/setup/dotctl.sh で導入する。"
fi
printf '\n\033[2m[press any key]\033[0m'
read -rsn1 || true
