#!/bin/bash
# herdr コールドスタート復元の純粋ロジック。
#
# herdr API の呼び出しやプロセス起動といった副作用は scripts/herdr-restore.sh
# （ドライバ）側に置き、ここは組み立てと判定だけを持つ。単体テストは
# scripts/test-herdr-restore.sh。

# マーカーの置き場。nvim 側の autocmd と同じく XDG_STATE_HOME を尊重する。
herdr_restore_state_dir() {
  printf '%s/%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}" "$1"
}

# pane_id から workspace ID を取り出す。"w5:p29" -> "w5"
herdr_restore_workspace_of() {
  printf '%s\n' "${1%%:*}"
}

# claude マーカーから起動コマンドを組み立てる。
# マーカーは3行: session_id / cwd / transcript_path
# transcript が実在するときだけ --resume する。会話が消えていても
# プロセスは立てたいので、その場合は素の claude を返す。
herdr_restore_claude_command() {
  local marker="$1"
  local session_id transcript
  session_id=$(awk 'NR==1' "$marker" 2>/dev/null)
  transcript=$(awk 'NR==3' "$marker" 2>/dev/null)
  if [[ -n "$session_id" && -n "$transcript" && -f "$transcript" ]]; then
    printf 'claude --resume %s\n' "$session_id"
    return 0
  fi
  printf 'claude\n'
}

# 復元プランを実行順に出力する。1行 = "<kind>\t<pane_id>\t<command>"
#
# 順序: nvim を全部流してから claude。各種別の中はフォーカス中 workspace が先。
# nvim は軽いので先に流しても claude の開始をほとんど遅らせず、目に入るペインが
# 先に埋まる。同一グループ内は pane_id の辞書順にして順序を決定的にする。
herdr_restore_plan() {
  local nvim_dir="$1" claude_dir="$2" alive_file="$3" focused_ws="$4"
  local group kind dir want_focused marker pane ws is_focused cmd

  for group in nvim-focused nvim-other claude-focused claude-other; do
    case "$group" in
      nvim-focused)
        kind=nvim
        dir="$nvim_dir"
        want_focused=1
        ;;
      nvim-other)
        kind=nvim
        dir="$nvim_dir"
        want_focused=0
        ;;
      claude-focused)
        kind=claude
        dir="$claude_dir"
        want_focused=1
        ;;
      claude-other)
        kind=claude
        dir="$claude_dir"
        want_focused=0
        ;;
    esac
    [[ -d "$dir" ]] || continue

    while IFS= read -r marker; do
      [[ -n "$marker" ]] || continue
      pane=$(basename "$marker")
      grep -Fxq "$pane" "$alive_file" || continue
      ws=$(herdr_restore_workspace_of "$pane")
      is_focused=0
      [[ "$ws" == "$focused_ws" ]] && is_focused=1
      [[ "$is_focused" == "$want_focused" ]] || continue
      if [[ "$kind" == "nvim" ]]; then
        cmd="nvim"
      else
        cmd=$(herdr_restore_claude_command "$marker")
      fi
      printf '%s\t%s\t%s\n' "$kind" "$pane" "$cmd"
    done < <(find "$dir" -maxdepth 1 -type f 2>/dev/null | sort)
  done
}

# 生存していないペインのマーカーを削除する。
# alive_file が空のときはペイン一覧の取得に失敗したとみなし、何も消さない。
herdr_restore_prune_markers() {
  local dir="$1" alive_file="$2"
  [[ -d "$dir" ]] || return 0
  [[ -s "$alive_file" ]] || return 0

  local marker pane
  while IFS= read -r marker; do
    [[ -n "$marker" ]] || continue
    pane=$(basename "$marker")
    grep -Fxq "$pane" "$alive_file" && continue
    rm -f "$marker"
  done < <(find "$dir" -maxdepth 1 -type f 2>/dev/null | sort)
}

# `herdr pane process-info` の JSON を読み、素のシェルなら 0 を返す。
# 前面プロセスがシェル自身なら idle、別 pid なら何か動いている。
herdr_restore_pane_is_idle() {
  local json="$1"
  local shell_pid fg_pid
  shell_pid=$(printf '%s' "$json" | jq -r '.result.process_info.shell_pid // empty' 2>/dev/null)
  fg_pid=$(printf '%s' "$json" | jq -r '.result.process_info.foreground_processes[0].pid // empty' 2>/dev/null)
  [[ -n "$shell_pid" && "$shell_pid" == "$fg_pid" ]]
}
