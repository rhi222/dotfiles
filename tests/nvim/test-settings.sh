#!/usr/bin/env bash
# 新規ファイルで推測材料が無くても、一般的な形式はspace、タブに意味がある形式だけhard tabにする。
# TypeScriptのroot markerは種類の優先ではなく、3種類のうち最寄りを選ぶ。
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

env -u HERDR_PANE_ID nvim --headless -u NONE -i NONE \
  -l "$SCRIPT_DIR/settings_spec.lua" \
  "$REPO_ROOT/.config/nvim"
