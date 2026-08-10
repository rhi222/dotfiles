#!/bin/bash
# Slackリアクション起票のうち、状態変更を担う部分。
#
# 役割分担: 判断（スレの要約・タイトル生成）は skill が行い、
# 状態変更（重複チェック・起票・seen追記）はこのスクリプトが行う。
# 夜間dispatchで push と PR作成をスクリプト側に寄せたのと同じ理由で、
# 権限層を通らない素のbashに副作用を集める。
#
# 使い方:
#   linear-slack-sweep.sh unseen <key>...
#   linear-slack-sweep.sh create <key> <permalink> <title> <outcome> <summary>
#
# key の形式は <channel_id>/<message_ts>。permalink はスレ内メッセージだと
# ?thread_ts= や &cid= が付いて文字列が揺れるため、重複判定のキーには使わない。
set -euo pipefail

# $0 ではなく BASH_SOURCE を使う（source されても lib を解決できるようにする）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/linear-api.sh"

SEEN="${LINEAR_SLACK_SWEEP_SEEN:-$HOME/.local/state/linear-slack-sweep/seen.txt}"
# 1回のスイープで処理する上限。スレを読む前の関門で切ると、
# LLMの読解コストごと止まる
LINEAR_SLACK_SWEEP_MAX="${LINEAR_SLACK_SWEEP_MAX:-20}"

seen_has() {
  [[ -f "$SEEN" ]] || return 1
  grep -qxF "$1" "$SEEN"
}

cmd_unseen() {
  local key count=0
  for key in "$@"; do
    [[ -n "$key" ]] || continue
    if seen_has "$key"; then continue; fi
    if [[ "$count" -ge "$LINEAR_SLACK_SWEEP_MAX" ]]; then break; fi
    echo "$key"
    count=$((count + 1))
  done
}

usage() {
  cat >&2 <<'EOF'
usage:
  linear-slack-sweep.sh unseen <key>...
  linear-slack-sweep.sh create <key> <permalink> <title> <outcome> <summary>
EOF
  return 2
}

main() {
  local sub="${1:-}"
  [[ "$#" -gt 0 ]] && shift
  case "$sub" in
    unseen) cmd_unseen "$@" ;;
    *) usage ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
