#!/usr/bin/env bash
# herdr 'prefix+a' helper: popup内でfzf → 選んだ agent のペインへフォーカス移動
# tmux の choose-tree 的な操作を fzf で行う。alt 系キーが効かない環境向けの代替。
#
# herdr agent list (JSON) を fzf に流し、選択行の pane_id を herdr agent focus に渡す。

set -eu

# 1列目(pane_id)は表示せず(--with-nth 2..)、選択後に cut で取り出す
lines=$(herdr agent list | jq -r '
  .result.agents[]
  | "\(.pane_id)\t\(.agent_status)\t\(.terminal_title_stripped)\t[\(.workspace_id)/\(.tab_id)]"')
[ -n "$lines" ] || exit 0

selected=$(
  printf '%s\n' "$lines" \
    | fzf --layout reverse --delimiter '\t' --with-nth 2.. \
          --prompt 'agent> ' --header 'focus agent'
)
[ -n "$selected" ] || exit 0

pane_id=$(printf '%s' "$selected" | cut -f1)
[ -n "$pane_id" ] || exit 0

herdr agent focus "$pane_id"
