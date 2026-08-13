#!/bin/bash
# herdr のペインで動いている claude を記録する。
#
# reboot 後に fish の `he` ラッパーがこのマーカーを読んで、該当ペインで
# `claude --resume <session_id>` を復元起動する。nvim 側の autocmd
# (.config/nvim/lua/my/settings/autocmd.lua) と対称な作りにしている。
#
# SessionEnd（正常終了）ではマーカーを消す。OS shutdown では hook が走らず
# マーカーが残る＝「claude が動いていたペイン」が残る。
# 1ペイン=1ファイルにすることで複数 claude 間の読み書き競合を避ける。
#
# 使い方: settings.json の hooks から `herdr-claude-marker.sh start|end` で呼ぶ。
set -uo pipefail

mode="${1:-}"
pane="${HERDR_PANE_ID:-}"

# herdr の外で起動した claude は対象外。
[[ -n "$pane" ]] || exit 0

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-claude"
marker="$state_dir/$pane"

case "$mode" in
  start)
    payload=$(cat)
    session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
    cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
    transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
    [[ -n "$session_id" ]] || exit 0
    mkdir -p "$state_dir"
    printf '%s\n%s\n%s\n' "$session_id" "$cwd" "$transcript" >"$marker"
    ;;
  end)
    # 自分が書いたマーカーでなければ消さない。
    #
    # 1ペインで旧セッションが終わって新セッションが始まることがある
    # （worktree に入ると session_id も project dir も変わる）。無条件に消すと、
    # 新セッションが書いたマーカーを旧セッションの end が持っていき、その
    # ペインは復元対象から丸ごと外れる。
    #
    # session_id が読めないときは判定材料が無いので従来どおり消す。残すと
    # 死んだセッションのマーカーが溜まり、復元で余計な claude が立つ。
    payload=$(cat)
    session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
    current=$(awk 'NR==1' "$marker" 2>/dev/null)
    if [[ -z "$session_id" || "$session_id" == "$current" ]]; then
      rm -f "$marker"
    fi
    ;;
  *)
    echo "usage: $(basename "$0") start|end" >&2
    exit 2
    ;;
esac

exit 0
