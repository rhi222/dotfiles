#!/bin/bash
# herdr コールドスタート復元の純粋ロジック。
#
# herdr API の呼び出しやプロセス起動といった副作用は scripts/herdr-restore.sh
# （ドライバ）側に置き、ここは組み立てと判定だけを持つ。単体テストは
# tests/session/test-herdr-restore.sh。

# マーカーの置き場。nvim 側の autocmd と同じく XDG_STATE_HOME を尊重する。
herdr_restore_state_dir() {
  printf '%s/%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}" "$1"
}

# pane_id から workspace ID を取り出す。"w5:p29" -> "w5"
herdr_restore_workspace_of() {
  printf '%s\n' "${1%%:*}"
}

# 復元プランを実行順に出力する。1行 = "<kind>\t<pane_id>\t<command>"
#
# フォーカス中 workspace を先にし、同一グループ内は pane_id の辞書順にする。
herdr_restore_plan() {
  local nvim_dir="$1" alive_file="$2" focused_ws="$3"
  local group want_focused marker pane ws is_focused

  for group in nvim-focused nvim-other; do
    case "$group" in
      nvim-focused)
        want_focused=1
        ;;
      nvim-other)
        want_focused=0
        ;;
    esac
    [[ -d "$nvim_dir" ]] || continue

    while IFS= read -r marker; do
      [[ -n "$marker" ]] || continue
      pane=$(basename "$marker")
      grep -Fxq "$pane" "$alive_file" || continue
      ws=$(herdr_restore_workspace_of "$pane")
      is_focused=0
      [[ "$ws" == "$focused_ws" ]] && is_focused=1
      [[ "$is_focused" == "$want_focused" ]] || continue
      printf 'nvim\t%s\tnvim\n' "$pane"
    done < <(find "$nvim_dir" -maxdepth 1 -type f 2>/dev/null | sort)
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

# ---- 復元の進行状況 ---------------------------------------------------------
#
# 投入は数分に散るため、走っているのか終わったのかを外から見えるようにする。
# 状態は key=value の行で1ファイルに持ち、`--status` の表示とトースト通知の
# 両方がここから文字列を組み立てる。
#
# 現在時刻の取得やプロセスの生存確認といった副作用はドライバ側に置き、ここへは
# 引数で渡す。整形を時計やプロセス状態に依存させないため。

# 状態ファイルを初期値で作る。
herdr_restore_status_init() {
  local file="$1" pid="$2" started_at="$3" nvim_total="$4"
  local tmp="$file.$$.tmp"
  mkdir -p "$(dirname "$file")"
  {
    printf 'state=running\n'
    printf 'pid=%s\n' "$pid"
    printf 'started_at=%s\n' "$started_at"
    printf 'finished_at=\n'
    printf 'reason=\n'
    printf 'nvim_total=%s\n' "$nvim_total"
    printf 'nvim_done=0\n'
    printf 'nvim_skipped=0\n'
  } >"$tmp"
  mv -f "$tmp" "$file"
}

# 1キーを読み出す。ファイルもキーも無ければ空を返す。
herdr_restore_status_get() {
  local file="$1" key="$2" line
  [[ -f "$file" ]] || return 0
  while IFS= read -r line; do
    if [[ "$line" == "$key="* ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  done <"$file"
}

# 1キーを更新する。読み手が書きかけの行を読まないよう tmp + mv で置き換える。
herdr_restore_status_set() {
  local file="$1" key="$2" value="$3"
  local tmp="$file.$$.tmp"
  local found=0 line
  mkdir -p "$(dirname "$file")"
  : >"$tmp"
  if [[ -f "$file" ]]; then
    while IFS= read -r line; do
      if [[ "$line" == "$key="* ]]; then
        printf '%s=%s\n' "$key" "$value" >>"$tmp"
        found=1
      else
        printf '%s\n' "$line" >>"$tmp"
      fi
    done <"$file"
  fi
  ((found == 1)) || printf '%s=%s\n' "$key" "$value" >>"$tmp"
  mv -f "$tmp" "$file"
}

# 数値キーを1増やす。数値でなければ0から数え直す。
herdr_restore_status_bump() {
  local file="$1" key="$2" current
  current=$(herdr_restore_status_get "$file" "$key")
  [[ "$current" =~ ^[0-9]+$ ]] || current=0
  herdr_restore_status_set "$file" "$key" "$((current + 1))"
}

herdr_restore_status_finish() {
  local file="$1" state="$2" finished_at="$3" reason="${4:-}"
  herdr_restore_status_set "$file" state "$state"
  herdr_restore_status_set "$file" finished_at "$finished_at"
  herdr_restore_status_set "$file" reason "$reason"
}

# 秒を「3分18秒」のような日本語表記にする。
# 大きい単位が出たら小さいほうは丸める（読み流せる長さに保つため）。
herdr_restore_format_duration() {
  local total="${1:-0}" hours minutes seconds
  [[ "$total" =~ ^[0-9]+$ ]] || total=0

  if ((total < 60)); then
    printf '%d秒\n' "$total"
    return 0
  fi

  seconds=$((total % 60))
  minutes=$((total / 60))
  if ((minutes < 60)); then
    if ((seconds == 0)); then
      printf '%d分\n' "$minutes"
    else
      printf '%d分%d秒\n' "$minutes" "$seconds"
    fi
    return 0
  fi

  hours=$((minutes / 60))
  minutes=$((minutes % 60))
  if ((minutes == 0)); then
    printf '%d時間\n' "$hours"
  else
    printf '%d時間%d分\n' "$hours" "$minutes"
  fi
}

# 件数を1行にまとめる。
# done と total が食い違う理由がその場でわかるようにするため。
herdr_restore_counts_summary() {
  local nvim_done="$1" nvim_total="$2" nvim_skipped="$3"
  local out

  out=$(printf 'nvim %s/%s' "$nvim_done" "$nvim_total")
  if ((nvim_skipped > 0)); then
    out=$(printf '%s (%d件は使用中でスキップ)' "$out" "$nvim_skipped")
  fi
  printf '%s\n' "$out"
}

herdr_restore_reason_text() {
  case "$1" in
    pane-list) printf 'ペイン一覧を取得できませんでした\n' ;;
    '') printf '原因不明\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# 状態ファイルを1行の表示にする。
# alive はドライバが `kill -0` で調べた pid の生存（1 or 0）。
# state=running のまま pid が居なければ「中断」として出す。
herdr_restore_status_render() {
  local file="$1" now="$2" alive="$3"
  local state started_at finished_at reason counts elapsed

  if [[ ! -f "$file" ]]; then
    printf 'herdr 復元: 記録なし\n'
    return 0
  fi

  state=$(herdr_restore_status_get "$file" state)
  reason=$(herdr_restore_status_get "$file" reason)
  if [[ "$state" == "failed" ]]; then
    printf 'herdr 復元: 失敗  %s\n' "$(herdr_restore_reason_text "$reason")"
    return 0
  fi

  started_at=$(herdr_restore_status_get "$file" started_at)
  finished_at=$(herdr_restore_status_get "$file" finished_at)
  [[ "$started_at" =~ ^[0-9]+$ ]] || started_at=0
  [[ "$finished_at" =~ ^[0-9]+$ ]] || finished_at="$started_at"
  [[ "$now" =~ ^[0-9]+$ ]] || now="$started_at"

  counts=$(herdr_restore_counts_summary \
    "$(herdr_restore_status_get "$file" nvim_done)" \
    "$(herdr_restore_status_get "$file" nvim_total)" \
    "$(herdr_restore_status_get "$file" nvim_skipped)")

  if [[ "$state" == "done" ]]; then
    elapsed=$(herdr_restore_format_duration "$((finished_at - started_at))")
    printf 'herdr 復元: 完了  %s  所要 %s\n' "$counts" "$elapsed"
    return 0
  fi

  elapsed=$(herdr_restore_format_duration "$((now - started_at))")
  if [[ "$alive" == "1" ]]; then
    printf 'herdr 復元: 実行中  %s  経過 %s\n' "$counts" "$elapsed"
  else
    printf 'herdr 復元: 中断  %s  開始から %s (プロセス不在)\n' "$counts" "$elapsed"
  fi
}

herdr_restore_toast_start_body() {
  printf 'nvim %s件を順に起動します\n' "$1"
}

herdr_restore_toast_done_body() {
  local counts elapsed
  counts=$(herdr_restore_counts_summary "$1" "$2" "$3")
  elapsed=$(herdr_restore_format_duration "$4")
  printf '%s / 所要 %s\n' "$counts" "$elapsed"
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
