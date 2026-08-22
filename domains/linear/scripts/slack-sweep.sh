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
#   linear-slack-sweep.sh create <key> <permalink> <title> <outcome> <summary> [label...]
#
# key の形式は <channel_id>/<message_ts>。permalink はスレ内メッセージだと
# ?thread_ts= や &cid= が付いて文字列が揺れるため、重複判定のキーには使わない。
set -euo pipefail

# $0 ではなく BASH_SOURCE を使う（source されても lib を解決できるようにする）
DOMAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/api.sh
source "$DOMAIN_DIR/lib/api.sh"

SEEN="${LINEAR_SLACK_SWEEP_SEEN:-$HOME/.local/state/linear-slack-sweep/seen.txt}"
LOCK="${LINEAR_SLACK_SWEEP_LOCK:-$HOME/.local/state/linear-slack-sweep/sweep.lock}"
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

seen_add() {
  mkdir -p "$(dirname "$SEEN")"
  echo "$1" >>"$SEEN"
}

# permalink_core <permalink>
# クエリ文字列を落として /archives/<CID>/p<TS> だけにする。
# Slackの「リンクをコピー」とAPIが返すpermalinkでクエリが違うため、
# 照合はこの中核部分だけで行う
permalink_core() {
  sed -E 's|^.*(/archives/[^/?]+/p[0-9]+).*$|\1|' <<<"$1"
}

# linear_find_by_url <url-core> → {id, identifier} または {}
# searchableContent はタイトルと本文の両方を見る（description より広い）。
# includeArchived を付けるのは autoArchivePeriod が1ヶ月で、
# 少し前のissueはアーカイブ側に居るため
linear_find_by_url() {
  local team
  team=$(linear_config '.team_id') || return 1
  linear_gql 'query($team: ID!, $q: String!) {
    issues(filter: {team: {id: {eq: $team}}, searchableContent: {contains: $q}},
           includeArchived: true, first: 1) {
      nodes { id identifier }
    }
  }' "$(jq -n --arg t "$team" --arg q "$1" '{team: $t, q: $q}')" | jq '.issues.nodes[0] // {}'
}

# 起票時に受け付ける推定ラベル。skillがスレを読んで判断した role/em だけを通す。
#
# 許可リストで弾くのは、agentがラベル名を1文字間違えたときに起票ごと落とさないため。
# linear_label_id は未知キーで非0を返すので、そのまま渡すと issueCreate が失敗し、
# seen にも入らないまま毎回同じ失敗を繰り返して永久に起票されない。
# 推定は付加価値であって起票の前提ではないので、壊れたラベルは捨てて起票を通す。
#
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
  local key="$1" permalink="$2" title="$3" outcome="$4" summary="$5"
  shift 5
  local labels=("src:slack") l
  for l in "$@"; do
    [[ -n "$l" ]] || continue
    if label_allowed "$l"; then
      labels+=("$l")
    else
      echo "linear-slack-sweep: 未知のラベルを無視する: $l" >&2
    fi
  done

  # seen判定→起票→seen追記 を排他にする。skill は create をキーごとに
  # 別プロセスで呼ぶので、cron（8:10）と手動起動が重なると両方が
  # seen判定を通過して同じスレを2回起票しうる。
  #
  # linear-sweep.sh の flock は -n（取れなければ即終了）だが、こちらは待つ。
  # あちらは同じスイープの二重起動なので後発を捨ててよいが、こちらは
  # キーごとに1プロセスなので捨てるとそのメッセージだけ起票されずに落ちる。
  mkdir -p "$(dirname "$LOCK")"
  exec 9>"$LOCK"
  flock 9

  if seen_has "$key"; then
    echo "skipped(seen) $key"
    return 0
  fi
  local body created ident core hit issue_id
  core=$(permalink_core "$permalink")
  hit=$(linear_find_by_url "$core") || return 1
  issue_id=$(jq -r '.id // ""' <<<"$hit")
  if [[ -n "$issue_id" ]]; then
    ident=$(jq -r '.identifier' <<<"$hit")
    # 同じスレが再燃したときにissueを増やさない。
    # ポインタの司令塔なので、issueとスレは1:1に保つ。
    # ラベルも触らない。既にtriageを通って人間が付け直しているかもしれない分類を、
    # スレを読み直しただけの機械が上書きしない
    linear_comment "$issue_id" "$(printf 'Slackで再言及: %s\n\n%s\n' "$permalink" "$summary")" || return 1
    seen_add "$key"
    echo "commented $ident"
    return 0
  fi
  body=$(printf '元URL: %s\n\n期待アウトカム: %s\n\n## 経緯\n%s\n' "$permalink" "$outcome" "$summary")
  created=$(linear_issue_create "$title" "$body" "Triage" "${labels[@]}") || return 1
  ident=$(jq -r '.identifier' <<<"$created")
  seen_add "$key"
  echo "created $ident"
}

usage() {
  cat >&2 <<'EOF'
usage:
  linear-slack-sweep.sh unseen <key>...
  linear-slack-sweep.sh create <key> <permalink> <title> <outcome> <summary> [label...]

label は role:player / role:manager / em:people / em:tech / em:project / em:product のみ。
それ以外は無視して起票を続ける。src:slack はスクリプトが固定で付ける
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
