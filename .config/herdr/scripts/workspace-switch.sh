#!/usr/bin/env bash
# herdr 'prefix+shift+s' helper: popup内でfzf → 選んだ workspace(spaces) へフォーカス移動
# agent-switch.sh の workspace 版。alt 系キーが効かない環境向けの代替。
#
# herdr workspace list (JSON) を fzf に流し、選択行の workspace_id を herdr workspace focus に渡す。

set -eu

# 1列目(workspace_id)は表示せず(--with-nth 2..)、選択後に cut で取り出す
lines=$(herdr workspace list | jq -r '
  .result.workspaces[]
  | "\(.workspace_id)\t#\(.number)\t\(.label)\t(\(.tab_count) tabs, \(.pane_count) panes)"')
[ -n "$lines" ] || exit 0

selected=$(
  printf '%s\n' "$lines" \
    | fzf --layout reverse --delimiter '\t' --with-nth 2.. \
          --prompt 'space> ' --header 'focus workspace'
)
[ -n "$selected" ] || exit 0

ws_id=$(printf '%s' "$selected" | cut -f1)
[ -n "$ws_id" ] || exit 0

herdr workspace focus "$ws_id"
