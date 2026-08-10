#!/bin/bash
# linear-slack-sweep.sh のテスト。curlをstubにする
#
# 重要: Slackへは一切書き込まない設計なので、このスクリプトはSlack APIを呼ばない。
# Slack側の読み取りはskillがMCPで行い、ここには結果だけが引数で渡る。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/linear-slack-sweep.sh"
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
export LINEAR_SLACK_SWEEP_SEEN="$tmp/state/seen.txt"
export LINEAR_SLACK_SWEEP_LOCK="$tmp/state/sweep.lock"

# --- unseen ---

# 1. seen.txt が無くても落ちず、全件返す
out1=$(bash "$SCRIPT" unseen "C1/1.1" "C1/2.2" 2>&1)
check "seen.txtが無くても全件返す" test "$out1" = "C1/1.1
C1/2.2"

# 2. seen済みのキーを除外する
printf 'C1/1.1\n' >"$LINEAR_SLACK_SWEEP_SEEN"
out2=$(bash "$SCRIPT" unseen "C1/1.1" "C1/2.2" 2>&1)
check "seen済みを除外する" test "$out2" = "C1/2.2"

# 3. 部分一致では除外しない（完全一致のみ）
printf 'C1/1.1\n' >"$LINEAR_SLACK_SWEEP_SEEN"
out3=$(bash "$SCRIPT" unseen "C1/1.11" 2>&1)
check "部分一致では除外しない" test "$out3" = "C1/1.11"

# 4. 上限で打ち切る
: >"$LINEAR_SLACK_SWEEP_SEEN"
keys=()
for i in $(seq 1 25); do keys+=("C1/$i.0"); done
out4=$(LINEAR_SLACK_SWEEP_MAX=20 bash "$SCRIPT" unseen "${keys[@]}" 2>&1)
check "上限20件で打ち切る" test "$(wc -l <<<"$out4")" -eq 20

# stub curl: 重複なし（issues.nodes が空）→ issueCreate 成功 を返す。
# payloadは1行、それ以外の引数は "ARGS:" 行に分けて記録する
# （ARGS行にpayloadを混ぜると payload の grep -c が二重に数えてしまう）
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
                "issueCreate": {"success": true, "issue": {"id": "i1", "identifier": "NSY-100", "url": "u"}}}}'
EOF
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
export CURL_LOG="$tmp/curl.log"

# --- create（重複なし） ---
: >"$LINEAR_SLACK_SWEEP_SEEN"
: >"$CURL_LOG"
PERMALINK="https://example.slack.com/archives/C0EXAMPLE/p1786335015733309?thread_ts=1784699205.854559&cid=C0EXAMPLE"
out6=$(bash "$SCRIPT" create "C0EXAMPLE/1786335015.733309" "$PERMALINK" \
  "PMS疎通試験の結果をまとめる" "試験結果を共有し、次の判断材料にする" "スレで疎通試験の話が出た" 2>&1)
check "createがcreatedを返す" grep -q "^created NSY-100$" <<<"$out6"
check "seenにキーが追記される" grep -qxF "C0EXAMPLE/1786335015.733309" "$LINEAR_SLACK_SWEEP_SEEN"
check "issueCreateが呼ばれる" grep -q "issueCreate" "$CURL_LOG"
check "Triageに起票する" grep -q "st-triage" "$CURL_LOG"
check "src:slackラベルが付く" grep -q "lb-s" "$CURL_LOG"
check "role/emラベルは付けない" test "$(grep -c 'lb-rp\|lb-et' "$CURL_LOG")" -eq 0
check "本文に元URLが入る" grep -q "元URL" "$CURL_LOG"
check "本文に期待アウトカムが入る" grep -q "期待アウトカム" "$CURL_LOG"

# --- create（seen済みなら何もしない） ---
: >"$CURL_LOG"
out7=$(bash "$SCRIPT" create "C0EXAMPLE/1786335015.733309" "$PERMALINK" "t" "o" "s" 2>&1)
check "seen済みならskippedを返す" grep -q "^skipped(seen)" <<<"$out7"
check "seen済みならAPIを呼ばない" test ! -s "$CURL_LOG"

# --- create（重複あり） ---
# stub curl を差し替え、issues.nodes に既存issueを1件返させる
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

: >"$LINEAR_SLACK_SWEEP_SEEN"
: >"$CURL_LOG"
out8=$(bash "$SCRIPT" create "C0EXAMPLE/9999.0" "$PERMALINK" "t" "o" "スレが再燃した" 2>&1)
check "重複時はcommentedを返す" grep -q "^commented NSY-42$" <<<"$out8"
check "重複時はissueCreateを呼ばない" test "$(grep -c 'issueCreate' "$CURL_LOG")" -eq 0
check "重複時はcommentCreateを呼ぶ" grep -q "commentCreate" "$CURL_LOG"
check "重複時もseenに追記する" grep -qxF "C0EXAMPLE/9999.0" "$LINEAR_SLACK_SWEEP_SEEN"
# 照合はpermalinkのクエリ文字列を落とした中核部分だけで行う
check "重複チェックは中核部分で照合する" grep -q '/archives/C0EXAMPLE/p1786335015733309' "$CURL_LOG"
check "重複チェックのクエリにthread_tsを含めない" \
  test "$(grep -c 'searchableContent.*thread_ts' "$CURL_LOG")" -eq 0

# 5. 未知のサブコマンドは usage を出して非0で終わる
bash "$SCRIPT" bogus >/dev/null 2>&1
check "未知のサブコマンドで非0終了する" test $? -ne 0

echo "---"
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
