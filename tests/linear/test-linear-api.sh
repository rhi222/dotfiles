#!/bin/bash
# Linear API層はGraphQLエラーを成功扱いせず、設定済みIDとstateを正確に返す。
# curlをstubに差し替え、実HTTPや共有systemへの書き込みは発生させない。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
LIB="$SCRIPTS_DIR/lib/linear-api.sh"
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

# --- fixture環境 ---
tmp=$(mktemp -d)
mkdir -p "$tmp/config/linear" "$tmp/bin"
echo "lin_api_test" >"$tmp/config/linear/api-key"
cat >"$tmp/config/linear/config.json" <<'EOF'
{
  "team_id": "team-uuid-1",
  "states": {"Triage": "st-triage", "Todo": "st-todo", "AI Queued": "st-ready", "AI Running": "st-run", "My Review": "st-judge", "Waiting": "st-wait", "Done": "st-done"},
  "labels": {"src:github": "lb-gh", "src:jira": "lb-jira"}
}
EOF

# stub curl: 受け取ったpayloadを記録し、CURL_RESPONSE の中身を返す
cat >"$tmp/bin/curl" <<'EOF'
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
: >"$CURL_LOG"
# shellcheck source=/dev/null  # 検査対象のパスは実行時に決まる
source "$LIB"

# 1. config読み出し
TEAM_ID=$(jq -r '.team_id' "$LINEAR_CONFIG_DIR/config.json")
READY_STATE_ID=$(jq -r '.states["AI Queued"]' "$LINEAR_CONFIG_DIR/config.json")
TRIAGE_STATE_ID=$(jq -r '.states.Triage' "$LINEAR_CONFIG_DIR/config.json")
GITHUB_LABEL_ID=$(jq -r '.labels["src:github"]' "$LINEAR_CONFIG_DIR/config.json")
check "linear_configがteam_idを返す" test "$(linear_config '.team_id')" = "$TEAM_ID"
check "linear_state_idが解決できる" test "$(linear_state_id 'AI Queued')" = "$READY_STATE_ID"
check "linear_label_idが解決できる" test "$(linear_label_id 'src:github')" = "$GITHUB_LABEL_ID"
check "未知のstate名は非0" bash -c "source '$LIB'; ! linear_state_id 'NoSuch'"

# 2. linear_gql 正常系: .data を返す
echo '{"data": {"viewer": {"id": "u1"}}}' >"$tmp/ok.json"
export CURL_RESPONSE="$tmp/ok.json"
check "linear_gqlが.dataを返す" test "$(linear_gql '{ viewer { id } }' | jq -r '.viewer.id')" = "u1"

# 3. linear_gql エラー系: errors[]があれば非0
echo '{"data": null, "errors": [{"message": "boom"}]}' >"$tmp/err.json"
check "GraphQLエラーで非0" bash -c "source '$LIB'; export CURL_RESPONSE='$tmp/err.json'; ! linear_gql '{ viewer { id } }'"

# 4. linear_issue_create がmutationを発行しissueを返す
#    viewerとissueCreateの2回curlが呼ばれるため、レスポンスは両方を含む形にする
cat >"$tmp/create.json" <<'EOF'
{"data": {"viewer": {"id": "user-me"},
          "issueCreate": {"success": true, "issue": {"id": "i1", "identifier": "NSY-1", "url": "https://linear.app/nsym/issue/NSY-1"}}}}
EOF
export CURL_RESPONSE="$tmp/create.json"
CREATED_IDENTIFIER=$(jq -r '.data.issueCreate.issue.identifier' "$CURL_RESPONSE")
: >"$CURL_LOG"
out=$(linear_issue_create "title x" "desc y" "Triage" "src:github")
check "issue_createがidentifierを返す" test "$(jq -r '.identifier' <<<"$out")" = "$CREATED_IDENTIFIER"
check "payloadにstateIdが入る" grep -q "$TRIAGE_STATE_ID" "$CURL_LOG"
check "payloadにlabelIdが入る" grep -q "$GITHUB_LABEL_ID" "$CURL_LOG"
check "payloadにassigneeIdが入る（My Issuesに出すため）" grep -q 'user-me' "$CURL_LOG"

# 5. linear_issues_in_state がnodes配列を返す
echo '{"data": {"issues": {"nodes": [{"id": "i1", "identifier": "NSY-1", "title": "t", "description": "d", "url": "u"}]}}}' >"$tmp/list.json"
export CURL_RESPONSE="$tmp/list.json"
check "issues_in_stateが配列を返す" test "$(linear_issues_in_state 'AI Queued' | jq 'length')" = "1"

# 6. linear_issue_move / linear_comment が成功する
echo '{"data": {"issueUpdate": {"success": true}}}' >"$tmp/move.json"
export CURL_RESPONSE="$tmp/move.json"
check "issue_moveが成功する" linear_issue_move "i1" "My Review"
echo '{"data": {"commentCreate": {"success": true}}}' >"$tmp/comment.json"
export CURL_RESPONSE="$tmp/comment.json"
check "commentが成功する" linear_comment "i1" "body"

# 7. linear_activity_since: 指定日時以降に更新されたissueを返す
cat >"$tmp/activity.json" <<'EOF'
{"data": {"issues": {"nodes": [
  {"identifier": "NSY-1", "title": "t1", "url": "u1", "updatedAt": "2026-08-06T10:00:00Z",
   "state": {"name": "Done", "type": "completed"},
   "labels": {"nodes": [{"name": "role:player"}, {"name": "em:tech"}]},
   "project": {"name": "P1"}, "parent": null}
]}}}
EOF
export CURL_RESPONSE="$tmp/activity.json"
: >"$CURL_LOG"
check "activity_sinceが配列を返す" test "$(linear_activity_since '2026-08-06' | jq 'length')" = "1"
check "activity_sinceがstateを含む" test "$(linear_activity_since '2026-08-06' | jq -r '.[0].state.name')" = "Done"
check "activity_sinceがラベルを含む" test "$(linear_activity_since '2026-08-06' | jq -r '.[0].labels.nodes[0].name')" = "role:player"
check "payloadに指定日時が入る" grep -q '2026-08-06' "$CURL_LOG"

# 配分の集計にCanceledが混ざると「ラベル未設定」が水増しされるため除外する
# （Doneは成果なので残す。Canceled/Duplicateだけを外す）
check "canceledを除外するフィルタを送る" grep -q 'canceled' "$CURL_LOG"

# 8. linear_cycle_issues: アクティブなCycleのissueを返す
#
# 「今日やる3件」の候補と、Cycle内の親子二重計上チェックの両方で使う。
# 絞り込みは呼び出し側がjqでやるので、ここではCycleの中身をそのまま返す。
cat >"$tmp/cycle.json" <<'EOF'
{"data": {"cycles": {"nodes": [
  {"number": 1, "startsAt": "2026-08-09T00:00:00Z", "endsAt": "2026-08-16T00:00:00Z",
   "issues": {"nodes": [
     {"identifier": "NSY-65", "title": "親", "url": "u1", "estimate": 2, "dueDate": null,
      "state": {"name": "Todo", "type": "unstarted"}, "labels": {"nodes": []},
      "parent": null, "children": {"nodes": [{"identifier": "NSY-66"}]}},
     {"identifier": "NSY-66", "title": "子", "url": "u2", "estimate": 1, "dueDate": null,
      "state": {"name": "Todo", "type": "unstarted"}, "labels": {"nodes": [{"name": "em:tech"}]},
      "parent": {"identifier": "NSY-65"}, "children": {"nodes": []}}
   ]}}
]}}}
EOF
export CURL_RESPONSE="$tmp/cycle.json"
PARENT_IDENTIFIER=$(jq -r '.data.cycles.nodes[0].issues.nodes[1].parent.identifier' "$CURL_RESPONSE")
CHILD_IDENTIFIER=$(jq -r '.data.cycles.nodes[0].issues.nodes[0].children.nodes[0].identifier' "$CURL_RESPONSE")
: >"$CURL_LOG"
check "cycle_issuesが配列を返す" test "$(linear_cycle_issues | jq 'length')" = "2"
check "cycle_issuesがestimateを含む" test "$(linear_cycle_issues | jq -r '.[0].estimate')" = "2"
check "cycle_issuesがparentを含む" test "$(linear_cycle_issues | jq -r '.[1].parent.identifier')" = "$PARENT_IDENTIFIER"
check "cycle_issuesがchildrenを含む" test "$(linear_cycle_issues | jq -r '.[0].children.nodes[0].identifier')" = "$CHILD_IDENTIFIER"
check "cycle_issuesがstateを含む" test "$(linear_cycle_issues | jq -r '.[0].state.name')" = "Todo"
# 「今週やると宣言したもの」だけを見たいので、進行中のCycleに限定する
check "アクティブなCycleに限定するフィルタを送る" grep -q 'isActive' "$CURL_LOG"
check "team_idで絞る" grep -q "$TEAM_ID" "$CURL_LOG"

# Cycleが1本も無い / 未開始の週は空配列を返す。日報作成やtriageを止めないため
echo '{"data": {"cycles": {"nodes": []}}}' >"$tmp/cycle-empty.json"
export CURL_RESPONSE="$tmp/cycle-empty.json"
check "アクティブなCycleが無ければ空配列" test "$(linear_cycle_issues | jq -c '.')" = "[]"

rm -rf "$tmp"
echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
