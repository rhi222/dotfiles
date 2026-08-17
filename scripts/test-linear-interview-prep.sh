#!/bin/bash
# linear-interview-prep.sh のテスト。curlをstubにする
#
# 重要: Google Calendar へは一切書き込まない。カレンダーの読み取りは skill が MCP で行い、
# ここには結果だけが引数で渡る（Linear → 外部の一方向リンクの原則）。
#
# 実在の候補者名・メールは絶対に置かない。このリポジトリは public なので、
# フィクスチャは架空名（候補者A）と架空の event id で組む。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/linear-interview-prep.sh"
pass=0
fail=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "NG: $desc"
    fail=$((fail + 1))
  fi
}

tmp=$(mktemp -d)
mkdir -p "$tmp/home/.config/linear" "$tmp/state" "$tmp/bin"
echo "lin_api_test" >"$tmp/home/.config/linear/api-key"
cat >"$tmp/home/.config/linear/config.json" <<'EOF'
{"team_id": "t1",
 "states": {"Triage": "st-triage", "Todo": "st-todo", "AI Queued": "st-r", "AI Running": "st-x", "My Review": "st-j", "Waiting": "st-w", "Done": "st-d"},
 "labels": {"src:github": "lb-gh", "src:jira": "lb-jira", "src:slack": "lb-s", "src:mtg": "lb-m", "role:player": "lb-rp", "role:manager": "lb-rm", "em:people": "lb-ep", "em:tech": "lb-et", "em:project": "lb-epj", "em:product": "lb-epd"}}
EOF

export LINEAR_CONFIG_DIR="$tmp/home/.config/linear"
export LINEAR_INTERVIEW_PREP_SEEN="$tmp/state/seen.txt"
export LINEAR_INTERVIEW_PREP_LOCK="$tmp/state/prep.lock"

EVT="evt0example000000000000001"
EVT_URL="https://www.google.com/calendar/event?eid=EXAMPLE"
PREP="- [ ] 経歴と志望動機を確認する
- [ ] 逆質問への回答を用意する"

# --- unseen ---

out1=$(bash "$SCRIPT" unseen "$EVT" "evt0example000000000000002" 2>&1)
check "seen.txtが無くても全件返す" test "$out1" = "$EVT
evt0example000000000000002"

printf '%s\n' "$EVT" >"$LINEAR_INTERVIEW_PREP_SEEN"
out2=$(bash "$SCRIPT" unseen "$EVT" "evt0example000000000000002" 2>&1)
check "seen済みを除外する" test "$out2" = "evt0example000000000000002"

# event id は前方一致しうる（同じ接頭辞の別イベント）ので完全一致で判定する
printf '%s\n' "$EVT" >"$LINEAR_INTERVIEW_PREP_SEEN"
out3=$(bash "$SCRIPT" unseen "${EVT}9" 2>&1)
check "部分一致では除外しない" test "$out3" = "${EVT}9"

: >"$LINEAR_INTERVIEW_PREP_SEEN"
keys=()
for i in $(seq 1 15); do keys+=("evt-$i"); done
out4=$(LINEAR_INTERVIEW_PREP_MAX=10 bash "$SCRIPT" unseen "${keys[@]}" 2>&1)
check "上限10件で打ち切る" test "$(wc -l <<<"$out4")" -eq 10

# stub curl: 重複なし（issues.nodes が空）→ issueCreate 成功
cat >"$tmp/bin/curl" <<'EOF'
#!/bin/bash
args=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--data" ]]; then echo "$2" >> "${CURL_LOG:?}"; shift 2
  else args="$args $1"; shift; fi
done
echo "ARGS:$args" >> "${CURL_LOG:?}"
echo '{"data": {"viewer": {"id": "user-me"},
                "issues": {"nodes": []},
                "issueCreate": {"success": true, "issue": {"id": "i1", "identifier": "NSY-200", "url": "u"}}}}'
EOF
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
export CURL_LOG="$tmp/curl.log"

# --- create（新規） ---
: >"$LINEAR_INTERVIEW_PREP_SEEN"
: >"$CURL_LOG"
out6=$(bash "$SCRIPT" create "$EVT" "面談準備: 候補者A (08/17 18:00)" \
  "2026-08-17 18:00" "$EVT_URL" "$PREP" "role:manager" "em:people" 2>&1)
check "createがcreatedを返す" grep -q "^created NSY-200$" <<<"$out6"
check "seenにevent idが追記される" grep -qxF "$EVT" "$LINEAR_INTERVIEW_PREP_SEEN"
check "issueCreateが呼ばれる" grep -q "issueCreate" "$CURL_LOG"
# Triage ではなく Todo。予定は確定済みで「やるか判断する」対象ではない
check "Todoに起票する" grep -q "st-todo" "$CURL_LOG"
check "Triageには入れない" test "$(grep -c 'st-triage' "$CURL_LOG")" -eq 0
check "src:mtgラベルが付く" grep -q "lb-m" "$CURL_LOG"
check "推定したroleラベルが付く" grep -q "lb-rm" "$CURL_LOG"
check "推定したemラベルが付く" grep -q "lb-ep" "$CURL_LOG"
# event id は二重防壁の2層目（Linear 側検索）のキーなので本文に必ず残す
check "本文にevent idが入る" grep -q "$EVT" "$CURL_LOG"
check "本文に予定URLが入る" grep -q "calendar" "$CURL_LOG"
check "本文に面談日時が入る" grep -q "2026-08-17 18:00" "$CURL_LOG"
check "本文に準備内容が入る" grep -q "逆質問" "$CURL_LOG"

# --- create（ラベル省略） ---
: >"$CURL_LOG"
out6b=$(bash "$SCRIPT" create "evt0example000000000000003" "t" "2026-08-18 10:00" "$EVT_URL" "$PREP" 2>&1)
check "ラベル省略でも起票できる" grep -q "^created NSY-200$" <<<"$out6b"
check "ラベル省略時もsrc:mtgは付く" grep -q "lb-m" "$CURL_LOG"

# --- create（未知のラベル名） ---
: >"$CURL_LOG"
out6c=$(bash "$SCRIPT" create "evt0example000000000000004" "t" "2026-08-18 10:00" "$EVT_URL" "$PREP" \
  "em:hiring" "role:manager" 2>&1)
check "未知のラベルがあっても起票は成功する" grep -q "^created NSY-200$" <<<"$out6c"
check "未知のラベルは無視して残りは付ける" grep -q "lb-rm" "$CURL_LOG"
check "未知のラベルを警告に出す" grep -q "em:hiring" <<<"$out6c"

# --- create（src:* は引数で受け付けない） ---
: >"$CURL_LOG"
bash "$SCRIPT" create "evt0example000000000000005" "t" "2026-08-18 10:00" "$EVT_URL" "$PREP" "src:slack" >/dev/null 2>&1
check "src:*を引数から付けない" test "$(grep -c 'lb-s' "$CURL_LOG")" -eq 0

# --- create（seen済みなら何もしない） ---
: >"$CURL_LOG"
out7=$(bash "$SCRIPT" create "$EVT" "t" "2026-08-17 18:00" "$EVT_URL" "$PREP" 2>&1)
check "seen済みならskippedを返す" grep -q "^skipped(seen)" <<<"$out7"
check "seen済みならAPIを呼ばない" test ! -s "$CURL_LOG"

# --- create（Linear側に既存 = seenが消えた端末） ---
cat >"$tmp/bin/curl" <<'EOF'
#!/bin/bash
args=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--data" ]]; then echo "$2" >> "${CURL_LOG:?}"; shift 2
  else args="$args $1"; shift; fi
done
echo "ARGS:$args" >> "${CURL_LOG:?}"
echo '{"data": {"viewer": {"id": "user-me"},
                "issues": {"nodes": [{"id": "i-old", "identifier": "NSY-42"}]},
                "commentCreate": {"success": true}}}'
EOF
chmod +x "$tmp/bin/curl"

: >"$LINEAR_INTERVIEW_PREP_SEEN"
: >"$CURL_LOG"
out8=$(bash "$SCRIPT" create "$EVT" "t" "2026-08-17 18:00" "$EVT_URL" "$PREP" "role:manager" 2>&1)
check "Linear側に既存ならskipped(exists)を返す" grep -q "^skipped(exists) NSY-42$" <<<"$out8"
check "既存があればissueCreateを呼ばない" test "$(grep -c 'issueCreate' "$CURL_LOG")" -eq 0
# 同じ予定を当日と前日で2回見ているだけなので、slack-sweep と違いコメントは付けない。
# 付けると毎朝コメントが増える
check "既存があってもコメントしない" test "$(grep -c 'commentCreate' "$CURL_LOG")" -eq 0
check "既存があってもseenに追記する" grep -qxF "$EVT" "$LINEAR_INTERVIEW_PREP_SEEN"
check "重複チェックはevent idで照合する" grep -q "$EVT" "$CURL_LOG"

# --- usage ---
bash "$SCRIPT" bogus >/dev/null 2>&1
check "未知のサブコマンドで非0終了する" test $? -ne 0

bash "$SCRIPT" create "only-one-arg" >/dev/null 2>&1
check "引数不足で非0終了する" test $? -ne 0

echo "---"
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
