#!/usr/bin/env bash
# tmux 'bind w' helper: tcmux のウィンドウ一覧を fzf で絞り込んで select-window する
#
# tcmux と fzf はmise shim経由でなくPATHにあれば動く。

set -eu

if ! command -v tcmux >/dev/null 2>&1; then
    tmux display-message "tcmux not found in PATH"
    exit 0
fi
if ! command -v fzf >/dev/null 2>&1; then
    tmux display-message "fzf not found in PATH"
    exit 0
fi

selected=$(tcmux lsw -A --color=always \
    | fzf --tmux 80%,50% --ansi --layout reverse --color='pointer:24' \
    | cut -d: -f 1)

[ -n "$selected" ] || exit 0

tmux select-window -t "$selected"
