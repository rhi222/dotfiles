#!/bin/bash
# herdr のコールドスタート後に nvim / claude を段階的に復元する。
#
# fish の `he` から setsid でバックグラウンド起動される想定。一斉起動による
# 負荷スパイクを避けるため、種別ごとに同時投入数と間隔を絞る。
#
#   --dry-run            何をどの順で流すかだけ出力して終わる
#   --session NAME       既定セッションではなく名前付きセッションを対象にする
#
# 調整用の環境変数:
#   HERDR_RESTORE_NVIM_BATCH      (既定 3)  nvim の同時投入数
#   HERDR_RESTORE_NVIM_INTERVAL   (既定 2)  nvim の次バッチまでの秒数
#   HERDR_RESTORE_CLAUDE_BATCH    (既定 1)  claude の同時投入数
#   HERDR_RESTORE_CLAUDE_INTERVAL (既定 8)  claude の次バッチまでの秒数
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/herdr-restore.sh
source "$SCRIPT_DIR/lib/herdr-restore.sh"

DRY_RUN=0
SESSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --session)
      SESSION="${2:-}"
      shift 2
      ;;
    *)
      echo "usage: $(basename "$0") [--dry-run] [--session NAME]" >&2
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
CLAUDE_DIR="$(herdr_restore_state_dir herdr-claude)"
NVIM_BATCH="${HERDR_RESTORE_NVIM_BATCH:-3}"
NVIM_INTERVAL="${HERDR_RESTORE_NVIM_INTERVAL:-2}"
CLAUDE_BATCH="${HERDR_RESTORE_CLAUDE_BATCH:-1}"
CLAUDE_INTERVAL="${HERDR_RESTORE_CLAUDE_INTERVAL:-8}"

# 多重起動を防ぐ。既に走っていれば黙って終わる。
LOCK="$(herdr_restore_state_dir herdr-restore.lock)"
mkdir -p "$(dirname "$LOCK")"
exec 9>"$LOCK"
flock -n 9 || exit 0

ALIVE=$(mktemp)
trap 'rm -f "$ALIVE"' EXIT

# ペイン一覧を取れなかった場合は、マーカーを消さずに何もしないで終わる。
pane_json=$(herdr_cli pane list 2>/dev/null) || exit 1
printf '%s' "$pane_json" | jq -e '.result.panes | type == "array"' >/dev/null 2>&1 || exit 1
printf '%s' "$pane_json" | jq -r '.result.panes[].pane_id' >"$ALIVE"
[[ -s "$ALIVE" ]] || exit 0

focused_ws=$(herdr_cli api snapshot 2>/dev/null | jq -r '.result.snapshot.focused_workspace_id // empty')

# マーカーディレクトリはセッション間で共有されている。名前付きセッションを
# 対象にしているときに掃除すると、既定セッションのマーカーを「死んだペイン」と
# 誤判定して全部消してしまう。掃除は既定セッションのときだけ行う。
if [[ "$DRY_RUN" -eq 0 && -z "$SESSION" ]]; then
  herdr_restore_prune_markers "$NVIM_DIR" "$ALIVE"
  herdr_restore_prune_markers "$CLAUDE_DIR" "$ALIVE"
fi

PLAN=()
while IFS= read -r line; do
  [[ -n "$line" ]] && PLAN+=("$line")
done < <(herdr_restore_plan "$NVIM_DIR" "$CLAUDE_DIR" "$ALIVE" "$focused_ws")

if [[ "$DRY_RUN" -eq 1 ]]; then
  for line in "${PLAN[@]}"; do
    printf '%s\n' "$line"
  done
  exit 0
fi

# 投入は数分に散るため、その間にユーザーが手でペインを使い始めうる。
# 直前に素のシェルかを確認し、何か動いていれば触らない。
launch() {
  local pane="$1" cmd="$2"
  local info
  info=$(herdr_cli pane process-info --pane "$pane" 2>/dev/null) || return 0
  herdr_restore_pane_is_idle "$info" || return 0
  herdr_cli pane run "$pane" "$cmd" >/dev/null 2>&1
}

run_group() {
  local kind="$1" batch="$2" interval="$3"
  local -a entries=()
  local line pane cmd i n

  for line in "${PLAN[@]}"; do
    [[ "${line%%$'\t'*}" == "$kind" ]] && entries+=("$line")
  done

  i=0
  while ((i < ${#entries[@]})); do
    n=0
    while ((n < batch && i < ${#entries[@]})); do
      IFS=$'\t' read -r _ pane cmd <<<"${entries[i]}"
      launch "$pane" "$cmd"
      i=$((i + 1))
      n=$((n + 1))
    done
    ((i < ${#entries[@]})) && sleep "$interval"
  done
}

run_group nvim "$NVIM_BATCH" "$NVIM_INTERVAL"
run_group claude "$CLAUDE_BATCH" "$CLAUDE_INTERVAL"
