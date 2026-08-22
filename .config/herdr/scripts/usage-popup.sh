#!/bin/bash
# prefix+u の popup: agent usage の詳細表示。任意のキーで閉じる。
set -uo pipefail

DOTCTL="${HERDR_USAGE_DOTCTL:-${HOME:-}/.local/bin/dotctl}"
if [ -x "$DOTCTL" ]; then
  "$DOTCTL" agent-usage detail
else
  echo "dotctl が見つからない。bash scripts/setup-dotctl.sh で導入する。"
fi
printf '\n[press any key]'
read -rsn1 || true
