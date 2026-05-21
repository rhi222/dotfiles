#!/usr/bin/env bash
# tmux 'bind f' helper: popup内でfzfファイル検索 → 選択パスを呼び出し元ペインに挿入
#
# Args:
#   $1: 検索開始ディレクトリ (pane_current_path)
#   $2: 送信先 pane_id

set -eu

start_dir="${1:?usage: fzf-file.sh <start_dir> <pane_id>}"
pane_id="${2:?usage: fzf-file.sh <start_dir> <pane_id>}"

cd "$start_dir" || exit 0

if command -v fd >/dev/null 2>&1; then
    list_cmd=(fd --type f --hidden --exclude .git)
else
    list_cmd=(find . -type f -not -path '*/.git/*')
fi

selected=$("${list_cmd[@]}" | fzf --tmux 80%,50% --layout reverse)
[ -n "$selected" ] || exit 0

tmux send-keys -t "$pane_id" "$selected"
