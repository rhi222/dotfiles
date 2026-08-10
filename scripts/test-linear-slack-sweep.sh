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

# 5. 未知のサブコマンドは usage を出して非0で終わる
bash "$SCRIPT" bogus >/dev/null 2>&1
check "未知のサブコマンドで非0終了する" test $? -ne 0

echo "---"
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
