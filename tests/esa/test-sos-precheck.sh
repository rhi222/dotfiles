#!/bin/bash
# scripts/esa/sos-precheck.sh のユニットテスト
#
# SoS事前記載確認スレの草稿は「未更新の記事だけに人をメンションする」ことで成立している。
# 判定を1つ誤ると、更新済みの人を催促する（信頼を削る）か、未更新の人を見逃す（定例が回らない）
# のどちらかが起きる。境界は次の2つで、どちらも off-by-one が入りやすいので固定する。
#
#   1. 前回SoS時刻の算出（実行日が木でも金でも土でも同じ週を指すこと）
#   2. FROMリビジョンの選定（前回SoS「より前」の最新。定例中〜定例後の編集は今週分に含める）
#
# curl は stub に差し替え、実HTTPを起こさない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/esa/sos-precheck.sh"

PASS=0
FAIL=0

assert_eq() {
  local expected="$1" actual="$2" name="$3"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_fails() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name（成功してしまった）"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  fi
}

if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT が存在しません"
  exit 1
fi

tmp=$(mktemp -d -t sos-precheck-test.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fixtures"

# --- curl stub -------------------------------------------------------------
# 引数の最後がURL。URLに対応するfixtureを返す。未定義URLは404相当（非ゼロ終了）。
cat >"$tmp/bin/curl" <<'STUB'
#!/bin/bash
url=""
for a in "$@"; do url="$a"; done
key=$(printf '%s' "$url" | tr -c 'A-Za-z0-9' '_')
f="${CURL_FIXTURES:?}/$key.json"
if [[ -f "$f" ]]; then cat "$f"; exit 0; fi
exit 22
STUB
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
export CURL_FIXTURES="$tmp/fixtures"
export ESA_ACCESS_TOKEN="dummy-token"

fixture() {
  local url="$1"
  local key
  key=$(printf '%s' "$url" | tr -c 'A-Za-z0-9' '_')
  cat >"$CURL_FIXTURES/$key.json"
}

api="https://api.esa.io/v1/teams/testteam"

echo "=== 前回SoS時刻の算出 ==="

assert_eq "2026-08-21T15:00:00+09:00" "$(bash "$SCRIPT" last-sos 2026-08-28)" \
  "金曜に実行したら前週金15:00（当日の定例はまだ先なので今週分に含める）"
assert_eq "2026-08-21T15:00:00+09:00" "$(bash "$SCRIPT" last-sos 2026-08-27)" \
  "木曜に実行しても同じ週を指す"
assert_eq "2026-08-21T15:00:00+09:00" "$(bash "$SCRIPT" last-sos 2026-08-24)" \
  "月曜に実行しても同じ週を指す"
assert_eq "2026-08-28T15:00:00+09:00" "$(bash "$SCRIPT" last-sos 2026-08-29)" \
  "土曜（定例後）は当週金15:00が前回になる"
echo ""

echo "=== FROMリビジョンの選定 ==="

revs='{"revisions":[
  {"number":5,"created_at":"2026-08-27T10:00:00+09:00"},
  {"number":4,"created_at":"2026-08-21T15:27:00+09:00"},
  {"number":3,"created_at":"2026-08-21T14:59:00+09:00"},
  {"number":2,"created_at":"2026-08-14T09:00:00+09:00"},
  {"number":1,"created_at":"2026-08-07T09:00:00+09:00"}
],"next_page":null}'

assert_eq "3" "$(printf '%s' "$revs" | bash "$SCRIPT" pick-from 2026-08-21T15:00:00+09:00)" \
  "前回SoSより前の最新を選ぶ（15:27は定例後なので今週分、選ばない）"
assert_eq "2" "$(printf '%s' "$revs" | bash "$SCRIPT" pick-from 2026-08-14T15:00:00+09:00)" \
  "基準をずらせば追随する"
assert_eq "1" "$(printf '%s' "$revs" | bash "$SCRIPT" pick-from 2026-08-01T15:00:00+09:00)" \
  "基準より前が1件も無ければ最古リビジョンにフォールバックする"

boundary='{"revisions":[
  {"number":2,"created_at":"2026-08-21T15:00:00+09:00"},
  {"number":1,"created_at":"2026-08-20T09:00:00+09:00"}
],"next_page":null}'
assert_eq "1" "$(printf '%s' "$boundary" | bash "$SCRIPT" pick-from 2026-08-21T15:00:00+09:00)" \
  "基準ちょうどのリビジョンは前回定例に映っていないので選ばない"
echo ""

echo "=== 更新判定とURL生成 ==="

cat >"$tmp/posts.json" <<'CONF'
{
  "team": "testteam",
  "posts": [
    { "post_number": 100, "label": "更新あり", "owner": "alice", "slack_id": "U_ALICE" },
    { "post_number": 200, "label": "未更新", "owner": "bob", "slack_id": "U_BOB" },
    { "post_number": 300, "label": "未更新だがメンション対象外", "mention": false, "link_style": "plain" },
    { "post_number": 500, "label": "担当者未設定", "owner": "", "slack_id": "U_NOBODY" }
  ]
}
CONF
export SOS_PRECHECK_CONFIG="$tmp/posts.json"

fixture "$api/posts/100/revisions?page=1&per_page=100" <<'EOF'
{"revisions":[
  {"number":12,"created_at":"2026-08-26T09:00:00+09:00"},
  {"number":11,"created_at":"2026-08-20T09:00:00+09:00"}
],"next_page":null}
EOF
fixture "$api/posts/200/revisions?page=1&per_page=100" <<'EOF'
{"revisions":[
  {"number":7,"created_at":"2026-08-19T09:00:00+09:00"}
],"next_page":null}
EOF
fixture "$api/posts/300/revisions?page=1&per_page=100" <<'EOF'
{"revisions":[
  {"number":3,"created_at":"2026-08-01T09:00:00+09:00"}
],"next_page":null}
EOF
fixture "$api/posts/500/revisions?page=1&per_page=100" <<'EOF'
{"revisions":[
  {"number":9,"created_at":"2026-08-01T09:00:00+09:00"}
],"next_page":null}
EOF

out=$(bash "$SCRIPT" check 2026-08-28)

assert_eq "true" "$(printf '%s' "$out" | jq -r '.[0].updated')" \
  "前回SoS以降にリビジョンが増えていれば更新あり"
assert_eq "https://testteam.esa.io/posts/100/revisions/compare/11...head/html_diff" \
  "$(printf '%s' "$out" | jq -r '.[0].url')" \
  "更新ありは compare URL（TOはheadで固定し、直前の追記も拾えるようにする）"
assert_eq "false" "$(printf '%s' "$out" | jq -r '.[0].mention')" \
  "更新済みの担当者はメンションしない"

assert_eq "false" "$(printf '%s' "$out" | jq -r '.[1].updated')" \
  "リビジョンが増えていなければ未更新"
assert_eq "https://testteam.esa.io/posts/200/revisions" \
  "$(printf '%s' "$out" | jq -r '.[1].url')" \
  "未更新は compare を作らず revisions 一覧を出す"
assert_eq "true" "$(printf '%s' "$out" | jq -r '.[1].mention')" \
  "未更新の担当者はメンション対象"
# 草稿には `@bob` と handle で書く。`<@U...>` のID表記は読み手が誰か判別できないので、
# 目視で誤メンションに気付けるように handle を宛先の正とする。
assert_eq "bob" "$(printf '%s' "$out" | jq -r '.[1].owner')" \
  "メンション先はhandleで返す"
assert_eq "U_BOB" "$(printf '%s' "$out" | jq -r '.[1].slack_id')" \
  "Slack IDも併せて返す（実メンションに切り替えたくなったとき用）"

assert_eq "https://testteam.esa.io/posts/300" \
  "$(printf '%s' "$out" | jq -r '.[2].url')" \
  "link_style=plain は記事URLだけを出す"
assert_eq "false" "$(printf '%s' "$out" | jq -r '.[2].mention')" \
  "mention=false の記事は未更新でもメンションしない"

# handle が無ければ草稿に書ける宛先が無い。IDだけ持っていても黙る
assert_eq "false" "$(printf '%s' "$out" | jq -r '.[3].mention')" \
  "owner未設定なら未更新でもメンションしない（slack_idだけでは書けない）"

assert_eq "4" "$(printf '%s' "$out" | jq -r 'length')" \
  "設定の並び順のまま全件返す"
echo ""

echo "=== 巨大なリビジョン応答 ==="

# esa の revisions は1リビジョンごとに body_md と body_html を丸ごと返す。
# 実データで1ページ8.6MBになり、判定に要らない本文を持ち回ったまま jq へ引数で
# 渡すと `Argument list too long` で落ちた。**番号と日時だけに削いでから積む**こと。
cat >"$tmp/posts-heavy.json" <<'CONF'
{ "team": "testteam",
  "posts": [ { "post_number": 400, "label": "重い記事", "owner": "carol", "slack_id": "U_CAROL" } ] }
CONF

python3 - "$CURL_FIXTURES" <<'PY'
import json, sys, pathlib, re
body = "x" * 40000  # 100件 × 40KB ≒ 4MB。ARG_MAX(概ね2MB)を確実に超える
revs = [{"number": n,
         "created_at": f"2026-08-{(n % 20) + 1:02d}T09:00:00+09:00",
         "body_md": body, "body_html": body}
        for n in range(1, 101)]
url = "https://api.esa.io/v1/teams/testteam/posts/400/revisions?page=1&per_page=100"
key = re.sub(r'[^A-Za-z0-9]', '_', url)
pathlib.Path(sys.argv[1], key + ".json").write_text(
    json.dumps({"revisions": revs, "next_page": None}))
PY

heavy=$(SOS_PRECHECK_CONFIG="$tmp/posts-heavy.json" bash "$SCRIPT" check 2026-08-28 2>&1)
assert_eq "100" "$(printf '%s' "$heavy" | jq -r '.[0].head_rev' 2>/dev/null)" \
  "本文を抱えた巨大な応答でも判定できる（最大のリビジョン番号を拾う）"
echo ""

echo "=== 週次議事録の動的解決 ==="

cat >"$tmp/posts-dynamic.json" <<'CONF'
{
  "team": "testteam",
  "posts": [
    { "dynamic": "weekly_minutes",
      "label": "週次議事録",
      "category": "01_x/Minutes/週次",
      "mention": false,
      "link_style": "plain" }
  ]
}
CONF

fixture "$api/posts?q=name%3A20260828%20in%3A01_x%2FMinutes%2F%E9%80%B1%E6%AC%A1&per_page=5" <<'EOF'
{"posts":[{"number":999,"full_name":"01_x/Minutes/週次/20260828"}],"total_count":1,"next_page":null}
EOF

out2=$(SOS_PRECHECK_CONFIG="$tmp/posts-dynamic.json" bash "$SCRIPT" check 2026-08-28)
assert_eq "https://testteam.esa.io/posts/999" "$(printf '%s' "$out2" | jq -r '.[0].url')" \
  "今週の金曜日付から週次議事録の記事番号を引く"

# 記事がまだ無い週でも草稿生成は止めない。人が手で足せるように穴を残す
out3=$(SOS_PRECHECK_CONFIG="$tmp/posts-dynamic.json" bash "$SCRIPT" check 2026-09-04)
assert_eq "null" "$(printf '%s' "$out3" | jq -r '.[0].post_number')" \
  "週次議事録が未作成でも落ちずに post_number=null を返す"
echo ""

echo "=== 事前チェック ==="

assert_fails "ESA_ACCESS_TOKEN 未設定なら失敗する" \
  env -u ESA_ACCESS_TOKEN bash "$SCRIPT" check 2026-08-28
assert_fails "設定ファイルが無ければ失敗する" \
  env SOS_PRECHECK_CONFIG="$tmp/does-not-exist.json" bash "$SCRIPT" check 2026-08-28
echo ""

echo "---"
echo "pass: $PASS 件 / fail: $FAIL 件"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
