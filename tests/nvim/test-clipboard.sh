#!/usr/bin/env bash
# ci-skip: win32yank.exe はWSLから見えるWindows側バイナリなのでCIに無い
# nvimのWSLクリップボード設定の結合テスト。詳細は clipboard_spec.lua のコメント。
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

env -u HERDR_PANE_ID nvim --headless -u NONE -i NONE \
  -l "$SCRIPT_DIR/clipboard_spec.lua" \
  "$REPO_ROOT/.config/nvim"
