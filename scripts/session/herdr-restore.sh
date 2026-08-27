#!/bin/bash
# herdr のコールドスタート後に nvim を段階的に復元する。
#
# fish の `he` から setsid でバックグラウンド起動される想定。一斉起動による
# 負荷スパイクを避けるため、種別ごとに同時投入数と間隔を絞る。
#
#   --dry-run            何をどの順で流すかだけ出力して終わる
#   --status             直近の復元がどこまで進んだかを1行で出して終わる
#   --session NAME       既定セッションではなく名前付きセッションを対象にする
#
# 進行状況は状態ファイルに残し、開始と完了で Windows トースト通知を出す。
# 投入が数分に散るため、走っているのか終わったのかを外から見えるようにする。
#
# 調整用の環境変数:
#   HERDR_RESTORE_NVIM_BATCH      (既定 3)  nvim の同時投入数
#   HERDR_RESTORE_NVIM_INTERVAL   (既定 2)  nvim の次バッチまでの秒数
# Claude / Codex の conversation は Herdr 本体の native agent restore が担当する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../internal/session/restore.sh
source "$SCRIPT_DIR/../../internal/session/restore.sh"

DRY_RUN=0
SHOW_STATUS=0
SESSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --status)
      SHOW_STATUS=1
      shift
      ;;
    --session)
      SESSION="${2:-}"
      shift 2
      ;;
    *)
      echo "usage: $(basename "$0") [--dry-run] [--status] [--session NAME]" >&2
      exit 2
      ;;
  esac
done

herdr_cli() {
  if [[ -n "$SESSION" ]]; then
    herdr --session "$SESSION" "$@"
  else
    herdr "$@"
  fi
}

NVIM_DIR="$(herdr_restore_state_dir herdr-nvim)"
STATUS="$(herdr_restore_state_dir herdr-restore.status)"
NVIM_BATCH="${HERDR_RESTORE_NVIM_BATCH:-3}"
NVIM_INTERVAL="${HERDR_RESTORE_NVIM_INTERVAL:-2}"
DOTCTL="${HERDR_RESTORE_DOTCTL:-$HOME/.local/bin/dotctl}"
[[ -x "$DOTCTL" ]] || DOTCTL="$(command -v dotctl 2>/dev/null || true)"

# WSL2 以外（powershell.exe が無い環境）では通知しない。
#
# **通知の完了は待たない。** BurntToast の読み込みに実測10秒前後かかり、
# reboot 直後のように混んでいるとさらに伸びる。通知は復元のついでなので、
# これで復元キューの頭とお尻が止まるのは割に合わない。
# 固まったまま残らないよう timeout で頭を抑えたうえで投げっぱなしにする。
notify() {
  command -v powershell.exe >/dev/null 2>&1 || return 0
  timeout 60 bash -c 'source "$1"; send_windows_toast "$2" "$3"' \
    _ "$SCRIPT_DIR/../lib/notify-windows-toast.sh" "$1" "$2" >/dev/null 2>&1 &
}

# 状態の表示。復元本体には触らないので、ロックより手前で処理して終わる
# （復元中は下の flock が取れず、黙って終わってしまうため）。
if [[ "$SHOW_STATUS" -eq 1 ]]; then
  status_pid=$(herdr_restore_status_get "$STATUS" pid)
  status_alive=0
  if [[ -n "$status_pid" ]] && kill -0 "$status_pid" 2>/dev/null; then
    status_alive=1
  fi
  herdr_restore_status_render "$STATUS" "$(date +%s)" "$status_alive"
  exit 0
fi

# 多重起動を防ぐ。既に走っていれば黙って終わる。
LOCK="$(herdr_restore_state_dir herdr-restore.lock)"
mkdir -p "$(dirname "$LOCK")"
exec 9>"$LOCK"
flock -n 9 || exit 0

PANE_FILE=$(mktemp)
PLAN_FILE=$(mktemp)
trap 'rm -f "$PANE_FILE" "$PLAN_FILE"' EXIT

fail() {
  local reason="$1"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    herdr_restore_status_finish "$STATUS" failed "$(date +%s)" "$reason"
    notify "⚠️ herdr 復元に失敗" "$(herdr_restore_reason_text "$reason")"
  fi
  exit 1
}

# ペイン一覧を取れなかった場合は、マーカーを消さずに何もしないで終わる。
pane_json=$(herdr_cli pane list 2>/dev/null) || fail pane-list
printf '%s' "$pane_json" | jq -e '.result.panes | type == "array"' >/dev/null 2>&1 || fail pane-list
printf '%s' "$pane_json" >"$PANE_FILE"
printf '%s' "$pane_json" | jq -e '.result.panes | length > 0' >/dev/null 2>&1 || exit 0

focused_ws=$(herdr_cli api snapshot 2>/dev/null | jq -r '.result.snapshot.focused_workspace_id // empty')
session_json=$(herdr session list --json 2>/dev/null) || fail session-list
session_name="${SESSION:-default}"
socket_path=$(printf '%s' "$session_json" | jq -r --arg name "$session_name" \
  '.sessions[]? | select(.name == $name and .running == true) | .socket_path' | head -n 1)
[[ -n "$socket_path" ]] || fail session-list
[[ -n "$DOTCTL" ]] || fail dotctl

planner_args=(session nvim-plan --markers "$NVIM_DIR" --panes "$PANE_FILE"
  --socket "$socket_path" --focused "$focused_ws")
# Version 1 markers predate per-session ownership and are only safe for default.
[[ -z "$SESSION" ]] && planner_args+=(--legacy)
"$DOTCTL" "${planner_args[@]}" >"$PLAN_FILE" 2>/dev/null || fail dotctl
jq -e '.entries | type == "array"' "$PLAN_FILE" >/dev/null 2>&1 || fail dotctl

if [[ "$DRY_RUN" -eq 0 ]]; then
  while IFS= read -r stale; do
    [[ "$stale" == "$NVIM_DIR/"* ]] && rm -f -- "$stale"
  done < <(jq -r '.stale[]' "$PLAN_FILE")
fi

PLAN=()
while IFS= read -r encoded; do
  [[ -n "$encoded" ]] && PLAN+=("$encoded")
done < <(jq -rc '.entries[] | @base64' "$PLAN_FILE")

if [[ "$DRY_RUN" -eq 1 ]]; then
  for line in "${PLAN[@]}"; do
    printf '%s' "$line" | base64 -d | jq -r '[.kind, .pane_id, .command] | @tsv'
  done
  exit 0
fi

READY_PLAN=()
for line in "${PLAN[@]}"; do
  pane=$(printf '%s' "$line" | base64 -d | jq -r '.pane_id')
  info=$(herdr_cli pane process-info --pane "$pane" 2>/dev/null) || continue
  herdr_restore_pane_is_idle "$info" || continue
  READY_PLAN+=("$line")
done
PLAN=("${READY_PLAN[@]}")
NVIM_TOTAL=${#PLAN[@]}

# 復元するものが無ければ、前回の記録を残したまま黙って終わる。
# 既にサーバーが動いている状態の `he` で通知が飛ぶのを避ける。
((NVIM_TOTAL > 0)) || exit 0

STARTED_AT=$(date +%s)
herdr_restore_status_init "$STATUS" "$$" "$STARTED_AT" "$NVIM_TOTAL"
notify "🔄 herdr 復元開始" "$(herdr_restore_toast_start_body "$NVIM_TOTAL")"

# 投入は数分に散るため、その間にユーザーが手でペインを使い始めうる。
# 直前に素のシェルかを確認し、何か動いていれば触らない。
#
# 触らなかった分は skipped に数える。done と total が食い違う理由が
# `--status` の表示だけでわかるようにするため。起動コマンド自体が失敗した
# 場合も、件数の辻褄を合わせるため skipped に入れる。
launch() {
  local kind="$1" pane="$2" cmd="$3"
  local info
  info=$(herdr_cli pane process-info --pane "$pane" 2>/dev/null) || {
    herdr_restore_status_bump "$STATUS" "${kind}_skipped"
    return 0
  }
  if ! herdr_restore_pane_is_idle "$info"; then
    herdr_restore_status_bump "$STATUS" "${kind}_skipped"
    return 0
  fi
  if herdr_cli pane run "$pane" "$cmd" >/dev/null 2>&1; then
    # pane runの受理だけでは起動成功ではない。前面processがnvimになるまで
    # 上限付きでpollし、command errorを「復元完了」に数えない。
    for _ in $(seq 1 40); do
      info=$(herdr_cli pane process-info --pane "$pane" 2>/dev/null) || info=""
      if herdr_restore_pane_is_nvim "$info"; then
        herdr_restore_status_bump "$STATUS" "${kind}_done"
        return 0
      fi
      sleep 0.25
    done
  fi
  herdr_restore_status_bump "$STATUS" "${kind}_skipped"
}

run_group() {
  local kind="$1" batch="$2" interval="$3"
  local -a entries=()
  local line pane cmd i n

  for line in "${PLAN[@]}"; do
    [[ "$(printf '%s' "$line" | base64 -d | jq -r '.kind')" == "$kind" ]] && entries+=("$line")
  done

  i=0
  while ((i < ${#entries[@]})); do
    n=0
    while ((n < batch && i < ${#entries[@]})); do
      line=$(printf '%s' "${entries[i]}" | base64 -d)
      pane=$(printf '%s' "$line" | jq -r '.pane_id')
      cmd=$(printf '%s' "$line" | jq -r '.command')
      launch "$kind" "$pane" "$cmd"
      i=$((i + 1))
      n=$((n + 1))
    done
    ((i < ${#entries[@]})) && sleep "$interval"
  done
}

run_group nvim "$NVIM_BATCH" "$NVIM_INTERVAL"

FINISHED_AT=$(date +%s)
herdr_restore_status_finish "$STATUS" "done" "$FINISHED_AT" ""
notify "✅ herdr 復元完了" "$(herdr_restore_toast_done_body \
  "$(herdr_restore_status_get "$STATUS" nvim_done)" \
  "$NVIM_TOTAL" \
  "$(herdr_restore_status_get "$STATUS" nvim_skipped)" \
  "$((FINISHED_AT - STARTED_AT))")"
