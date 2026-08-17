#!/bin/bash
# 面談・面接の準備タスクをLinearへ起票する部分。
#
# 役割分担: 判断（どの予定が面談か・準備に何が要るか）は nippo-add skill が行い、
# 状態変更（重複チェック・起票・seen追記）はこのスクリプトが行う。
# linear-slack-sweep.sh と同じで、権限層を通らない素のbashに副作用を集める。
#
# 使い方:
#   linear-interview-prep.sh unseen <event_id>...
#   linear-interview-prep.sh create <event_id> <title> <when> <event_url> <prep> [label...]
#
# 重複判定のキーは Google Calendar の event id。日時やタイトルは編集で揺れるが
# event id は不変で、**当日分と前日分で同じ予定を必ず2回拾う**この用途では
# キーの安定性がそのまま二重起票の有無になる。
#
# Google Calendar へは一切書き込まない。リンクは Linear → 外部の一方向のみ。
set -euo pipefail

# $0 ではなく BASH_SOURCE を使う（source されても lib を解決できるようにする）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/linear-api.sh"

SEEN="${LINEAR_INTERVIEW_PREP_SEEN:-$HOME/.local/state/linear-interview-prep/seen.txt}"
LOCK="${LINEAR_INTERVIEW_PREP_LOCK:-$HOME/.local/state/linear-interview-prep/prep.lock}"
# 1回で処理する上限。面談は多い日でも3〜4件なので、これを超えるのは
# 判定が壊れて無関係な予定を拾っている状態
LINEAR_INTERVIEW_PREP_MAX="${LINEAR_INTERVIEW_PREP_MAX:-10}"

seen_has() {
  [[ -f "$SEEN" ]] || return 1
  grep -qxF "$1" "$SEEN"
}

cmd_unseen() {
  local key count=0
  for key in "$@"; do
    [[ -n "$key" ]] || continue
    if seen_has "$key"; then continue; fi
    if [[ "$count" -ge "$LINEAR_INTERVIEW_PREP_MAX" ]]; then break; fi
    echo "$key"
    count=$((count + 1))
  done
}

seen_add() {
  mkdir -p "$(dirname "$SEEN")"
  echo "$1" >>"$SEEN"
}

# linear_find_by_event <event_id> → {id, identifier} または {}
# seen.txt が無い端末（新環境・state を消した後）でも二重起票しないための2層目。
# includeArchived を付けるのは autoArchivePeriod が1ヶ月で、
# 終わった面談のissueはアーカイブ側に居るため
linear_find_by_event() {
  local team
  team=$(linear_config '.team_id') || return 1
  linear_gql 'query($team: ID!, $q: String!) {
    issues(filter: {team: {id: {eq: $team}}, searchableContent: {contains: $q}},
           includeArchived: true, first: 1) {
      nodes { id identifier }
    }
  }' "$(jq -n --arg t "$team" --arg q "$1" '{team: $t, q: $q}')" | jq '.issues.nodes[0] // {}'
}

# 起票時に受け付ける推定ラベル。skillが予定を読んで判断した role/em だけを通す。
# 許可リストで弾く理由は linear-slack-sweep.sh と同じ（未知キーで起票ごと落とさない）。
# src:* は含めない。流入元は事実判定なのでスクリプトが固定で付ける
ALLOWED_LABELS=(
  "role:player" "role:manager"
  "em:people" "em:tech" "em:project" "em:product"
)

label_allowed() {
  local l
  for l in "${ALLOWED_LABELS[@]}"; do
    [[ "$l" == "$1" ]] && return 0
  done
  return 1
}

cmd_create() {
  local event_id="$1" title="$2" when="$3" event_url="$4" prep="$5"
  shift 5
  local labels=("src:mtg") l
  for l in "$@"; do
    [[ -n "$l" ]] || continue
    if label_allowed "$l"; then
      labels+=("$l")
    else
      echo "linear-interview-prep: 未知のラベルを無視する: $l" >&2
    fi
  done

  # seen判定→起票→seen追記 を排他にする。skill は create を予定ごとに別プロセスで
  # 呼ぶので、cron（8:00）と手動の /nippo-add が重なると両方が seen 判定を
  # 通過して同じ面談を2回起票しうる
  mkdir -p "$(dirname "$LOCK")"
  exec 9>"$LOCK"
  flock 9

  if seen_has "$event_id"; then
    echo "skipped(seen) $event_id"
    return 0
  fi

  local body created ident hit issue_id
  hit=$(linear_find_by_event "$event_id") || return 1
  issue_id=$(jq -r '.id // ""' <<<"$hit")
  if [[ -n "$issue_id" ]]; then
    ident=$(jq -r '.identifier' <<<"$hit")
    # コメントは付けない。slack-sweep はスレの「再燃」を拾うので追記に意味があるが、
    # こちらは同じ予定を前日と当日で2回見ているだけで、新しい事実は何も無い。
    # 付けると毎朝コメントが増えて、issueが読めなくなる
    seen_add "$event_id"
    echo "skipped(exists) $ident"
    return 0
  fi

  # カレンダーIDは重複判定の2層目が引く検索キーなので、可視の行として残す
  # （HTMLコメントに隠すと searchableContent に載るかがLinear側の実装依存になる）
  body=$(printf '面談日時: %s\n\n予定: %s\n\n## 準備\n\n%s\n\nカレンダーID: %s\n' \
    "$when" "$event_url" "$prep" "$event_id")

  # Triage ではなく Todo に入れる。Triage は「やるべきか判断する」箱だが、
  # 面談はカレンダーで確定済みで判断の余地が無い。Triageに積むと
  # 受け入れ操作が月8件増えるだけになる
  created=$(linear_issue_create "$title" "$body" "Todo" "${labels[@]}") || return 1
  ident=$(jq -r '.identifier' <<<"$created")
  seen_add "$event_id"
  echo "created $ident"
}

usage() {
  cat >&2 <<'EOF'
usage:
  linear-interview-prep.sh unseen <event_id>...
  linear-interview-prep.sh create <event_id> <title> <when> <event_url> <prep> [label...]

label は role:player / role:manager / em:people / em:tech / em:project / em:product のみ。
それ以外は無視して起票を続ける。src:mtg はスクリプトが固定で付ける
EOF
  return 2
}

main() {
  local sub="${1:-}"
  [[ "$#" -gt 0 ]] && shift
  case "$sub" in
    unseen) cmd_unseen "$@" ;;
    create)
      [[ "$#" -ge 5 ]] || usage
      cmd_create "$@"
      ;;
    *) usage ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
