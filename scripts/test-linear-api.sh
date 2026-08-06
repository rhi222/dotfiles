#!/bin/bash
# linear-api.sh のテスト。curlをstubに差し替えてHTTPを発生させない
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/lib/linear-api.sh"
pass=0; fail=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok: $desc"; pass=$((pass+1))
  else echo "NG: $desc"; fail=$((fail+1)); fi
}

# --- fixture環境 ---
tmp=$(mktemp -d)
mkdir -p "$tmp/config/linear" "$tmp/bin"
echo "lin_api_test" > "$tmp/config/linear/api-key"
cat > "$tmp/config/linear/config.json" <<'EOF'
{
  "team_id": "team-uuid-1",
  "states": {"Triage": "st-triage", "Todo": "st-todo", "AI Ready": "st-ready", "AI Running": "st-run", "判断待ち": "st-judge", "Done": "st-done"},
  "labels": {"ai:ready": "lb-ready", "src:github": "lb-gh", "src:jira": "lb-jira"}
}
EOF

# stub curl: 受け取ったpayloadを記録し、CURL_RESPONSE の中身を返す
cat > "$tmp/bin/curl" <<'EOF'
#!/bin/bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--data" ]]; then echo "$2" >> "${CURL_LOG:?}"; shift 2; else shift; fi
done
cat "${CURL_RESPONSE:?}"
EOF
chmod +x "$tmp/bin/curl"

export PATH="$tmp/bin:$PATH"
export LINEAR_CONFIG_DIR="$tmp/config/linear"
export CURL_LOG="$tmp/curl.log"
: > "$CURL_LOG"
source "$LIB"

# 1. config読み出し
check "linear_configがteam_idを返す" test "$(linear_config '.team_id')" = "team-uuid-1"
check "linear_state_idが解決できる" test "$(linear_state_id 'AI Ready')" = "st-ready"
check "linear_label_idが解決できる" test "$(linear_label_id 'ai:ready')" = "lb-ready"
check "未知のstate名は非0" bash -c "source '$LIB'; ! linear_state_id 'NoSuch'"

# 2. linear_gql 正常系: .data を返す
echo '{"data": {"viewer": {"id": "u1"}}}' > "$tmp/ok.json"
export CURL_RESPONSE="$tmp/ok.json"
check "linear_gqlが.dataを返す" test "$(linear_gql '{ viewer { id } }' | jq -r '.viewer.id')" = "u1"

# 3. linear_gql エラー系: errors[]があれば非0
echo '{"data": null, "errors": [{"message": "boom"}]}' > "$tmp/err.json"
check "GraphQLエラーで非0" bash -c "source '$LIB'; export CURL_RESPONSE='$tmp/err.json'; ! linear_gql '{ viewer { id } }'"

# 4. linear_issue_create がmutationを発行しissueを返す
#    viewerとissueCreateの2回curlが呼ばれるため、レスポンスは両方を含む形にする
cat > "$tmp/create.json" <<'EOF'
{"data": {"viewer": {"id": "user-me"},
          "issueCreate": {"success": true, "issue": {"id": "i1", "identifier": "NSY-1", "url": "https://linear.app/nsym/issue/NSY-1"}}}}
EOF
export CURL_RESPONSE="$tmp/create.json"
: > "$CURL_LOG"
out=$(linear_issue_create "title x" "desc y" "Triage" "src:github")
check "issue_createがidentifierを返す" test "$(jq -r '.identifier' <<<"$out")" = "NSY-1"
check "payloadにstateIdが入る" grep -q 'st-triage' "$CURL_LOG"
check "payloadにlabelIdが入る" grep -q 'lb-gh' "$CURL_LOG"
check "payloadにassigneeIdが入る（My Issuesに出すため）" grep -q 'user-me' "$CURL_LOG"

# 5. linear_issues_in_state がnodes配列を返す
echo '{"data": {"issues": {"nodes": [{"id": "i1", "identifier": "NSY-1", "title": "t", "description": "d", "url": "u"}]}}}' > "$tmp/list.json"
export CURL_RESPONSE="$tmp/list.json"
check "issues_in_stateが配列を返す" test "$(linear_issues_in_state 'AI Ready' | jq 'length')" = "1"

# 6. linear_issue_move / linear_comment が成功する
echo '{"data": {"issueUpdate": {"success": true}}}' > "$tmp/move.json"
export CURL_RESPONSE="$tmp/move.json"
check "issue_moveが成功する" linear_issue_move "i1" "判断待ち"
echo '{"data": {"commentCreate": {"success": true}}}' > "$tmp/comment.json"
export CURL_RESPONSE="$tmp/comment.json"
check "commentが成功する" linear_comment "i1" "body"

rm -rf "$tmp"
echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
