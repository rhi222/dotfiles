#!/usr/bin/env bash
# nvim 0.12.5 の `:restart` / `ZR` はセッションを保存して再起動後に復元する。
# auto-session はそれを知らないため、ガードが無いと二重に復元してバッファリストが
# 2セッション分の和になり、定期保存がその和を焼き付ける。
# 起動理由による復元可否と、その判定が auto-session.lua へ配線されていることを固定する。
# 検証内容は tests/session/nvim-restart-guard_spec.lua の冒頭コメントに書いてある。
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 実行中の herdr ペイン ID を継がせない。spec 側が自分で立てる。
env -u HERDR_PANE_ID -u AUTOSESSION_UNIT_TESTING \
  nvim --headless -u NONE -i NONE \
  -l "$SCRIPT_DIR/nvim-restart-guard_spec.lua" \
  "$REPO_ROOT/.config/nvim"
