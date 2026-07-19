#!/usr/bin/env bash
# herdr 'prefix+a' helper: popup内でfzf → 選んだ agent のペインへフォーカス移動
# tmux の choose-tree 的な操作を fzf で行う。alt 系キーが効かない環境向けの代替。
#
# herdr agent list (JSON) を fzf に流し、選択行の pane_id を herdr agent focus に渡す。
# 表示順: {状態アイコン} {space名} {tab名} {AIエージェント名} {タイトル}

set -eu

# 状態アイコン/色は herdr 本体(src/ui/status.rs の agent_icon)に合わせる:
#   ◉ blocked(red/31) / ⠋ working(yellow/33) / ● done(teal/36) / ✓ idle(green/32) / ○ unknown(gray/90)
# working は本体ではアニメする spinner だが、静的リストなので 1 フレームで代表させる。
# ESC はソースに直書きせず printf で生成し、jq に --arg で渡して色付けする（fzf は --ansi で解釈）。
esc=$(printf '\033')

# agent list には workspace_id / tab_id しか無いので、
# space名(workspace label) と tab名(tab label) を別途引いて id で結合する。
ws=$(herdr workspace list)
tabs=$(herdr tab list)

# 表示は 2列目に集約（1列目=pane_id はタブ区切りの隠しフィールド）。
# 各列(space/tab/agent)はスペースで固定幅に埋め、タブストップ非依存で桁を揃える。
lines=$(herdr agent list | jq -r --arg esc "$esc" --argjson ws "$ws" --argjson tabs "$tabs" '
  def pad($w): . + (($w - length) as $n | if $n < 1 then " " else " " * $n end);
  ($ws.result.workspaces | map({(.workspace_id): .label}) | add) as $wslabel
  | ($tabs.result.tabs | map({(.tab_id): .label}) | add) as $tablabel
  | {blocked:"31m◉", working:"33m⠋", done:"36m●", idle:"32m✓", unknown:"90m○"} as $c
  | .result.agents[]
  | (($c[.agent_status]) // "0m•") as $v
  | (($wslabel[.workspace_id]) // .workspace_id) as $sp
  | (($tablabel[.tab_id]) // (.tab_id | sub("^[^:]*:"; ""))) as $tb
  | (.agent // "?") as $a
  | "\(.pane_id)\t\($esc)[\($v)\($esc)[0m \($sp|pad(9))\($tb|pad(9))\($a|pad(8))\(.terminal_title_stripped)"')
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
