#!/usr/bin/env bash
# herdr 'prefix+t' helper: popup内でfzf → 選んだ tab へフォーカス移動
# agent-switch.sh / workspace-switch.sh の tab 版。herdr に tab の絞り込み検索が無いため補う
# （native の prefix+g は navigate mode で h/j/k/l の空間移動、prefix+1..9 は番号直打ち）。
#
# herdr tab list (JSON) を fzf に流し、選択行の tab_id を herdr tab focus に渡す。
# 表示順: {状態アイコン} {focus印} {space名} {tab名} ({pane数} panes)

set -eu

# tab の label は既定が番号なので複数 workspace で "1" が並ぶ。space 名が無いと
# 一覧から区別できないため、workspace list を引いて workspace_id で結合する。
# 引けなかった場合も一覧自体は出す（tab へ飛べないほうが困る）ので、
# 失敗は空 JSON に倒して workspace_id 表示へフォールバックさせる。
ws=$(herdr workspace list 2>/dev/null || printf '{}')

# 状態アイコン/色は agent-switch.sh と同じ（herdr 本体 src/ui/status.rs の agent_icon 準拠）:
#   ◉ blocked(31) / ⠋ working(33) / ● done(36) / ✓ idle(32) / ○ unknown(90)
# ESC はソースに直書きせず printf で生成し、jq に --arg で渡す（fzf は --ansi で解釈）。
esc=$(printf '\033')

# 表示は2列目に集約（1列目=tab_id はタブ区切りの隠しフィールド）。
# 各列はスペースで固定幅に埋め、タブストップ非依存で桁を揃える。
lines=$(herdr tab list | jq -r --arg esc "$esc" --argjson ws "$ws" '
  def pad($w): . + (($w - length) as $n | if $n < 1 then " " else " " * $n end);
  (($ws.result.workspaces // []) | map({(.workspace_id): .label}) | add) as $wslabel
  | {blocked:"31m◉", working:"33m⠋", done:"36m●", idle:"32m✓", unknown:"90m○"} as $c
  | (.result.tabs // [])[]
  | (($c[.agent_status // "unknown"]) // "0m•") as $v
  | (if .focused then "*" else " " end) as $m
  | (($wslabel[.workspace_id]) // .workspace_id // "?") as $sp
  | (.label // "?") as $tb
  | "\(.tab_id)\t\($esc)[\($v)\($esc)[0m \($m) \($sp|pad(12))\($tb|pad(14))(\(.pane_count) panes)"')
[ -n "$lines" ] || exit 0

# ESC の 130 で落ちないよう終了ステータスを飲む（set -e 下では代入ごと失敗するため）
selected=$(
  printf '%s\n' "$lines" |
    fzf --ansi --layout reverse --delimiter '\t' --with-nth 2.. \
      --prompt 'tab> ' --header 'focus tab' || true
)
[ -n "$selected" ] || exit 0

tab_id=$(printf '%s' "$selected" | cut -f1)
[ -n "$tab_id" ] || exit 0

herdr tab focus "$tab_id"
