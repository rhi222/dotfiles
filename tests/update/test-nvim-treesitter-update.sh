#!/bin/bash
# 今回の kulala_http 誤更新を検知する回帰テスト。
# 引数なしの TSUpdate は nvim-treesitter 管理tierだけを更新し、明示引数は維持する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

nvim --headless -u NONE -i NONE \
  -l "$SCRIPT_DIR/treesitter-update_spec.lua" \
  "$REPO_ROOT/.config/nvim/lua"
