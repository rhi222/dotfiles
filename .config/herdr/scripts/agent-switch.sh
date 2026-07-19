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

# 場所表示に workspace の内部ID(w9)ではなくラベル(daily)を使うため workspace list も引く。
# agent list には workspace_id しか無いので workspace_id→label の対応を作って結合する。
ws=$(herdr workspace list)

# 表示は 2列目に全部まとめる（1列目=pane_id はタブ区切りの隠しフィールド）。
# タブ区切りのまま複数列にするとエージェント名の長さ差でタブストップがずれるため、
# エージェント名をスペースで固定幅(8)に埋めて 2列目内で桁を揃える。
lines=$(herdr agent list | jq -r --arg esc "$esc" --argjson ws "$ws" '
  ($ws.result.workspaces | map({(.workspace_id): .label}) | add) as $label
  | {blocked:"31m◉", working:"33m⠋", done:"36m●", idle:"32m✓", unknown:"90m○"} as $c
  | .result.agents[]
  | (($c[.agent_status]) // "0m•") as $v
  | (($label[.workspace_id]) // .workspace_id) as $wl
  | (.tab_id | sub("^[^:]*:"; "")) as $tab
  | (.agent // "?") as $a
  | ($a + ((8 - ($a | length)) as $n | if $n < 1 then " " else " " * $n end)) as $ap
  | "\(.pane_id)\t\($esc)[\($v)\($esc)[0m \($ap)\(.terminal_title_stripped)  [\($wl)/\($tab)]"')
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
