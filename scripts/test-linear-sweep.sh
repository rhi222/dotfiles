#!/bin/bash
# linear-sweep.sh のテスト。gh/curlをstubにする
#
# 重要: 外部システム（GitHub/Jira）へ書き戻さないことを検証する。
# ghのstubは search/api/auth 以外で呼ばれたら exit 99 して落ちる。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/linear-sweep.sh"
pass=0; fail=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok: $desc"; pass=$((pass+1))
  else echo "NG: $desc"; fail=$((fail+1)); fi
}

tmp=$(mktemp -d)
mkdir -p "$tmp/home/.config/linear" "$tmp/home/.local/state" "$tmp/bin"
echo "lin_api_test" > "$tmp/home/.config/linear/api-key"
cat > "$tmp/home/.config/linear/config.json" <<'EOF'
{"team_id": "t1",
 "states": {"Triage": "st-triage", "Todo": "st-todo", "AI Ready": "st-r", "AI Running": "st-x", "判断待ち": "st-j", "Done": "st-d"},
 "labels": {"src:github": "lb-gh", "src:jira": "lb-jira", "ai:blocked-human": "lb-b", "src:slack": "lb-s", "src:esa": "lb-e", "src:todoist": "lb-t", "role:player": "lb-rp", "role:manager": "lb-rm", "em:people": "lb-ep", "em:tech": "lb-et", "em:project": "lb-epj", "em:product": "lb-epd"}}
EOF

# stub gh: 呼び出しを記録し、search 以外（書き込み系）が来たら異常終了する
cat > "$tmp/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >> "${GH_LOG:?}"
case "$1" in
  search|api|auth) ;;
  *) echo "gh stub: 書き込み系サブコマンドが呼ばれた: $1" >&2; exit 99 ;;
esac
# レビュー依頼で呼ばれたら異常終了する（スイープ対象外なので呼んではいけない）
if [[ "$*" == *review-requested* ]]; then
  echo "gh stub: レビュー依頼を検索した（対象外のはず）" >&2; exit 98
fi
# bot作成PRを1件混ぜて、除外されることを検証する
echo '[{"url": "https://github.com/example-org/repo1/pull/1", "title": "PR one", "author": {"login": "human-dev"}},
      {"url": "https://github.com/example-org/repo9/pull/9", "title": "bump foo", "author": {"login": "dependabot[bot]"}}]'
EOF
chmod +x "$tmp/bin/gh"

# stub curl: issueCreate成功を返す。
# payloadは1行、それ以外の引数は "ARGS:" 行に分けて記録する
# （ARGS行にpayloadを混ぜると payload の grep -c が二重に数えてしまう）
cat > "$tmp/bin/curl" <<'EOF'
#!/bin/bash
args=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--data" ]]; then echo "$2" >> "${CURL_LOG:?}"; shift 2
  else args="$args $1"; shift; fi
done
echo "ARGS:$args" >> "${CURL_LOG:?}"
# viewer は linear_issue_create が assigneeId 解決のために呼ぶ
echo '{"data": {"viewer": {"id": "user-me"},
                "issueCreate": {"success": true, "issue": {"id": "i1", "identifier": "NSY-9", "url": "u"}}}}'
EOF
chmod +x "$tmp/bin/curl"

export PATH="$tmp/bin:$PATH"
export CURL_LOG="$tmp/curl.log"
export GH_LOG="$tmp/gh.log"
: > "$CURL_LOG"; : > "$GH_LOG"

# 1. フラグなし → 静かにスキップ
out1=$(HOME="$tmp/home" bash "$SCRIPT" 2>&1)
check "フラグなしで静かにスキップ" test -z "$out1"

# 2. フラグあり → gh 2件がTriageに起票され、seenに記録される
touch "$tmp/home/.config/linear-sweep-enabled"
: > "$CURL_LOG"
HOME="$tmp/home" LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
seen="$tmp/home/.local/state/linear-sweep/seen.txt"
check "seenファイルにURLが記録される" grep -q "repo1/pull/1" "$seen"
check "issueCreateが呼ばれる" grep -q "issueCreate" "$CURL_LOG"
check "src:githubラベルが付く" grep -q "lb-gh" "$CURL_LOG"
check "Triageに起票される" grep -q "st-triage" "$CURL_LOG"
check "bot作成PRは起票しない" bash -c "! grep -q 'repo9/pull/9' '$CURL_LOG'"
check "bot作成PRはseenにも入れない" bash -c "! grep -q 'repo9/pull/9' '$seen'"
check "自分のdraft PRは起票される" grep -q "repo1/pull/1" "$CURL_LOG"
check "レビュー依頼は検索すらしない" bash -c "! grep -q 'review-requested' '$GH_LOG'"
check "起票タイトルはdraft仕上げ" grep -q 'draft仕上げ' "$CURL_LOG"
# src:* だけだと後からrole/emをバックフィルする羽目になるので起票時に確定させる
check "role:playerラベルが付く" grep -q 'lb-rp' "$CURL_LOG"
check "em:techラベルが付く" grep -q 'lb-et' "$CURL_LOG"

# 2-2. LINEAR_SWEEP_MAX で起票数を絞れる（gh stubは2種類の検索に各2件返すので計4件相当）
tmp2=$(mktemp -d)
mkdir -p "$tmp2/.config/linear" "$tmp2/.local/state"
cp "$tmp/home/.config/linear/api-key" "$tmp2/.config/linear/"
cp "$tmp/home/.config/linear/config.json" "$tmp2/.config/linear/"
touch "$tmp2/.config/linear-sweep-enabled"
: > "$CURL_LOG"
HOME="$tmp2" LINEAR_CONFIG_DIR="$tmp2/.config/linear" LINEAR_SWEEP_MAX=1 bash "$SCRIPT" >/dev/null 2>&1
check "LINEAR_SWEEP_MAX=1で1件しか起票しない" test "$(grep -c 'issueCreate' "$CURL_LOG")" = "1"
rm -rf "$tmp2"

# 3. 再実行 → seen済みは起票しない（冪等）
: > "$CURL_LOG"
HOME="$tmp/home" LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "2回目はissueCreateを呼ばない" bash -c "! grep -q issueCreate '$CURL_LOG'"

# 4. jira.envなし → Jiraはスキップ（エラーにならない）
check "jira.env無しでも正常終了" test -f "$seen"

# 4-2. --if-not-today: 当日まだ走っていなければ実行、走っていればスキップ
tmp3=$(mktemp -d)
mkdir -p "$tmp3/.config/linear" "$tmp3/.local/state"
cp "$tmp/home/.config/linear/api-key" "$tmp3/.config/linear/"
cp "$tmp/home/.config/linear/config.json" "$tmp3/.config/linear/"
touch "$tmp3/.config/linear-sweep-enabled"
lastrun="$tmp3/.local/state/linear-sweep/last-run"

out=$(HOME="$tmp3" LINEAR_CONFIG_DIR="$tmp3/.config/linear" bash "$SCRIPT" --if-not-today 2>&1)
check "初回は--if-not-todayでも実行する" grep -q "linear-sweep done" <<<"$out"
check "実行するとlast-runに当日日付を記録する" test "$(cat "$lastrun" 2>/dev/null)" = "$(date +%F)"

out=$(HOME="$tmp3" LINEAR_CONFIG_DIR="$tmp3/.config/linear" bash "$SCRIPT" --if-not-today 2>&1)
check "同日2回目は静かにスキップする" test -z "$out"

echo "2000-01-01" > "$lastrun"
out=$(HOME="$tmp3" LINEAR_CONFIG_DIR="$tmp3/.config/linear" bash "$SCRIPT" --if-not-today 2>&1)
check "last-runが古い日付なら実行する" grep -q "linear-sweep done" <<<"$out"

# --if-not-today が無ければ日付に関係なく毎回走る（cronからの呼び出し）
out=$(HOME="$tmp3" LINEAR_CONFIG_DIR="$tmp3/.config/linear" bash "$SCRIPT" 2>&1)
check "引数なしなら当日実行済みでも走る" grep -q "linear-sweep done" <<<"$out"
rm -rf "$tmp3"

# 5. 外部システムへの書き戻しをしない（read-onlyの強制）
check "ghはsearchしか呼ばない" bash -c "! grep -qvE '^(search|api|auth) ' '$GH_LOG'"
check "gh issue commentを呼ばない" bash -c "! grep -q 'issue comment' '$GH_LOG'"
check "gh pr commentを呼ばない" bash -c "! grep -q 'pr comment' '$GH_LOG'"
check "gh pr editを呼ばない" bash -c "! grep -q 'pr edit' '$GH_LOG'"
check "curlはLinear宛のみ（Jira等へPOSTしない）" bash -c "! grep -E '^ARGS:.*atlassian' '$CURL_LOG'"

rm -rf "$tmp"
echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
