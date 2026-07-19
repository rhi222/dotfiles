#!/usr/bin/env bash
# herdr 'prefix+a' helper: popup内でfzf → 選んだ agent のペインへフォーカス移動
# tmux の choose-tree 的な操作を fzf で行う。alt 系キーが効かない環境向けの代替。
#
# herdr agent list (JSON) を fzf に流し、選択行の pane_id を herdr agent focus に渡す。

set -eu

# 状態アイコン/色は herdr 本体(src/ui/status.rs の agent_icon)に合わせる:
#   ◉ blocked(red/31) / ⠋ working(yellow/33) / ● done(teal/36) / ✓ idle(green/32) / ○ unknown(gray/90)
# working は本体ではアニメする spinner だが、静的リストなので 1 フレームで代表させる。
# ESC はソースに直書きせず printf で生成し、jq に --arg で渡して色付けする（fzf は --ansi で解釈）。
esc=$(printf '\033')

# 1列目(pane_id)は無着色で置き、選択後に cut -f1 で取り出す（色は 2 列目のアイコンのみ）
# 2列目に「状態アイコン + AIエージェント名(claude/codex..)」を出す
lines=$(herdr agent list | jq -r --arg esc "$esc" '
  {blocked:"31m◉", working:"33m⠋", done:"36m●", idle:"32m✓", unknown:"90m○"} as $c
  | .result.agents[]
  | (($c[.agent_status]) // "0m•") as $v
  | "\(.pane_id)\t\($esc)[\($v)\($esc)[0m \(.agent // "?")\t\(.terminal_title_stripped)\t[\(.workspace_id)/\(.tab_id)]"')
[ -n "$lines" ] || exit 0

selected=$(
  printf '%s\n' "$lines" \
    | fzf --ansi --layout reverse --delimiter '\t' --with-nth 2.. \
          --prompt 'agent> ' --header 'focus agent'
)
[ -n "$selected" ] || exit 0

pane_id=$(printf '%s' "$selected" | cut -f1)
[ -n "$pane_id" ] || exit 0

herdr agent focus "$pane_id"
