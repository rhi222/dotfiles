#!/bin/bash
# SoS事前記載確認: 対象esa記事が前回SoS以降に更新されたかを判定する。
#
# 出力はJSONだけ。Slackへ投げる文面は skill 側（sos-precheck）が組み立てる。
# **判定と作文を分けている**のは、判定が決定的でテストできるのに対し、
# 文面はその週の事情（休みの人、代打、催促のトーン）で変わるため。
#
#   sos-precheck.sh last-sos  [YYYY-MM-DD]     前回SoS時刻を出す
#   sos-precheck.sh pick-from <CUTOFF>         stdinのrevisions JSONからFROMを選ぶ
#   sos-precheck.sh check     [YYYY-MM-DD]     全記事を判定してJSON配列を出す
#
# 環境変数:
#   ESA_ACCESS_TOKEN     必須
#   SOS_PRECHECK_CONFIG  設定JSON（既定: ~/.claude/skills/sos-precheck/sos-precheck-posts.json）
set -uo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

config_path() {
  if [[ -n "${SOS_PRECHECK_CONFIG:-}" ]]; then
    printf '%s' "$SOS_PRECHECK_CONFIG"
    return
  fi
  printf '%s' "$HOME/.claude/skills/sos-precheck/sos-precheck-posts.json"
}

# 前回SoSの時刻。
#
# 今回の定例 = 実行日以降の最初の金曜15:00（実行日が金曜ならその日）。
# 前回の定例 = その7日前。
#
# **金曜の午前に実行しても当日の定例を「前回」にしない**のが要点。草稿は定例の前に
# 投げるので、当日15:00を基準にすると今週の更新が丸ごと差分から消える。
last_sos() {
  local d="${1:-$(date +%F)}"
  local dow ahead this_fri
  dow=$(date -d "$d" +%u) || die "日付として読めない: $d"
  ahead=$(((5 - dow + 7) % 7))
  this_fri=$(date -d "$d +$ahead days" +%F)
  date -d "$this_fri -7 days" +%FT15:00:00+09:00
}

# 前回SoS「より前」に作成された最新リビジョン番号を返す。
#
# 境界を strictly before にするのは、定例中〜定例後（金15:00以降）の編集が
# 前回の場には映っていないため。ここを `<=` にするとFROMが1つ後ろにずれ、
# 「先週の定例後に書いた分」が今週の差分から抜け落ちる。
#
# 基準より前が1件も無ければ最古リビジョンへフォールバックする（記事が先週
# 作られた場合など）。
pick_from() {
  local cutoff="$1" cutoff_epoch
  cutoff_epoch=$(date -d "$cutoff" +%s) || die "基準時刻として読めない: $cutoff"
  jq -r --argjson cutoff "$cutoff_epoch" "$JQ_EPOCH"'
    [.revisions[] | {number, epoch: (.created_at | to_epoch)}]
    | (map(select(.epoch < $cutoff)) | max_by(.number) | .number) // (min_by(.number) | .number)
  '
}

# jq の fromdateiso8601 は末尾 Z しか受け付けないが、esa は `+09:00` を返す。
# **オフセットを捨てて日付部分だけ比べない**こと。SoSの境界が金15:00という
# 時刻なので、9時間ずれると木曜夜の編集が先週分に落ちる。
JQ_EPOCH='
def to_epoch:
  . as $s
  | ($s[0:19] + "Z" | fromdateiso8601) as $base
  | $s[19:] as $tz
  | if ($tz == "Z" or $tz == "") then $base
    else (($tz[1:3] | tonumber) * 3600 + ($tz[4:6] | tonumber) * 60) as $off
      | if $tz[0:1] == "-" then $base + $off else $base - $off end
    end;
'

esa_get() {
  curl -sf -H "Authorization: Bearer ${ESA_ACCESS_TOKEN}" "$1"
}

urlencode() {
  printf '%s' "$1" | jq -sRr @uri
}

# リビジョン一覧。cutoffより古いものが1件出るまでページを辿る。
#
# 検索の記事は毎週10件以上リビジョンが積むので、per_page=100でもいつか
# 1ページに収まらなくなる。**その日を待たずに辿っておく**（収まらなくなった週に
# 全記事が「更新なし」に化けて、全員を誤って催促することになるため）。
#
# **本文は受け取った直後に捨てる。** esa は1リビジョンごとに body_md と body_html を
# 丸ごと返すので、実データで1ページ8.6MBある。ここで削がずに持ち回ると、
# jq へ渡す時点で `Argument list too long` に当たる。判定に要るのは番号と日時だけ。
fetch_revisions() {
  local api="$1" number="$2" cutoff_epoch="$3"
  local page=1 acc='[]' body next oldest

  while :; do
    body=$(esa_get "${api}/posts/${number}/revisions?page=${page}&per_page=100") || return 1

    acc=$(printf '%s' "$body" |
      jq -c --argjson acc "$acc" '$acc + [.revisions[] | {number, created_at}]')

    oldest=$(printf '%s' "$acc" | jq -r "$JQ_EPOCH"'map(.created_at | to_epoch) | min')
    next=$(printf '%s' "$body" | jq -r '.next_page')

    [[ "$next" == "null" || -z "$next" ]] && break
    [[ "$oldest" != "null" && "$oldest" -lt "$cutoff_epoch" ]] && break
    page="$next"
  done

  printf '%s' "$acc" | jq '{revisions: .}'
}

# 週次議事録は毎週新しい記事が立つので番号を固定できない。
# カテゴリ配下の「今回の金曜日付」の記事を引く。未作成なら空を返して続行する
# （草稿生成を止めるほどの事ではなく、人が手で足せる）。
resolve_weekly_minutes() {
  local api="$1" category="$2" ref_date="$3"
  local dow ahead fri q body
  dow=$(date -d "$ref_date" +%u)
  ahead=$(((5 - dow + 7) % 7))
  fri=$(date -d "$ref_date +$ahead days" +%Y%m%d)

  q=$(urlencode "name:${fri} in:${category}")
  body=$(esa_get "${api}/posts?q=${q}&per_page=5") || return 0
  printf '%s' "$body" | jq -r --arg name "${category}/${fri}" '
    (.posts // []) | map(select(.full_name == $name)) | (.[0].number // empty)
  '
}

cmd_check() {
  local ref_date="${1:-$(date +%F)}"
  local conf
  conf=$(config_path)

  [[ -n "${ESA_ACCESS_TOKEN:-}" ]] || die "ESA_ACCESS_TOKEN が未設定"
  command -v jq >/dev/null 2>&1 || die "jq が無い"
  [[ -f "$conf" ]] || die "設定ファイルが無い: $conf"

  local team api cutoff cutoff_epoch count
  team=$(jq -r '.team // empty' "$conf")
  [[ -n "$team" ]] || die "設定に team が無い: $conf"
  api="https://api.esa.io/v1/teams/${team}"
  local web="https://${team}.esa.io"

  cutoff=$(last_sos "$ref_date")
  cutoff_epoch=$(date -d "$cutoff" +%s)
  count=$(jq '.posts | length' "$conf")

  local out='[]' i entry number label owner slack_id mention_cfg link_style dynamic
  for ((i = 0; i < count; i++)); do
    entry=$(jq -c ".posts[$i]" "$conf")
    label=$(jq -r '.label // ""' <<<"$entry")
    owner=$(jq -r '.owner // ""' <<<"$entry")
    slack_id=$(jq -r '.slack_id // ""' <<<"$entry")
    mention_cfg=$(jq -r 'if has("mention") then (.mention|tostring) else "true" end' <<<"$entry")
    link_style=$(jq -r '.link_style // "diff"' <<<"$entry")
    dynamic=$(jq -r '.dynamic // ""' <<<"$entry")

    local from_rev="null" head_rev="null" updated="null" url="null" number_json

    if [[ "$dynamic" == "weekly_minutes" ]]; then
      number=$(resolve_weekly_minutes "$api" "$(jq -r '.category' <<<"$entry")" "$ref_date")
      if [[ -n "$number" ]]; then url="\"${web}/posts/${number}\""; fi
    else
      number=$(jq -r '.post_number' <<<"$entry")
      local revs
      revs=$(fetch_revisions "$api" "$number" "$cutoff_epoch") ||
        die "リビジョンを取得できない: post ${number}"
      from_rev=$(printf '%s' "$revs" | pick_from "$cutoff")
      head_rev=$(printf '%s' "$revs" | jq -r '.revisions | max_by(.number) | .number')

      if [[ "$head_rev" -gt "$from_rev" ]]; then updated="true"; else updated="false"; fi

      if [[ "$link_style" == "plain" ]]; then
        url="\"${web}/posts/${number}\""
      elif [[ "$updated" == "true" ]]; then
        url="\"${web}/posts/${number}/revisions/compare/${from_rev}...head/html_diff\""
      else
        url="\"${web}/posts/${number}/revisions\""
      fi
    fi

    # メンションするのは「未更新」かつ「メンション対象」かつ「宛先がある」場合だけ。
    # 3条件のうち1つでも欠けたら黙る。誤って催促する方が、見逃すより回復しにくい。
    #
    # **宛先の正は handle（owner）。** 草稿は `@tinoue` と書く形にしているので、
    # slack_id だけ埋まっていても書ける宛先が無い。ここを slack_id で見ていると、
    # handle 未設定の記事が「メンション対象」として上がってきて草稿に穴が空く。
    local mention="false"
    if [[ "$updated" == "false" && "$mention_cfg" == "true" && -n "$owner" ]]; then
      mention="true"
    fi

    number_json=$([[ -n "$number" ]] && printf '%s' "$number" || printf 'null')

    out=$(jq -c \
      --argjson n "$number_json" \
      --arg label "$label" \
      --arg owner "$owner" \
      --arg slack_id "$slack_id" \
      --argjson from "$from_rev" \
      --argjson head "$head_rev" \
      --argjson updated "$updated" \
      --argjson url "$url" \
      --argjson mention "$mention" \
      '. + [{post_number: $n, label: $label, owner: $owner, slack_id: $slack_id,
             from_rev: $from, head_rev: $head, updated: $updated,
             url: $url, mention: $mention}]' <<<"$out")
  done

  printf '%s\n' "$out" | jq '.'
}

case "${1:-}" in
  last-sos) last_sos "${2:-}" ;;
  pick-from) pick_from "${2:?基準時刻が要る}" ;;
  check) cmd_check "${2:-}" ;;
  *)
    echo "usage: $(basename "$0") {last-sos|pick-from|check} [args]" >&2
    exit 2
    ;;
esac
