#!/bin/bash
# bootstrapは必要なstateとlabelが全て揃った場合だけ完全なconfigを保存し、
# 不足時は不完全なconfigを残さない。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
SCRIPT="$SCRIPTS_DIR/linear/bootstrap.sh"
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
mkdir -p "$tmp/config/linear" "$tmp/bin"
echo "lin_api_test" >"$tmp/config/linear/api-key"

cat >"$tmp/bin/curl" <<'EOF'
#!/bin/bash
cat "${CURL_RESPONSE:?}"
EOF
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
export LINEAR_CONFIG_DIR="$tmp/config/linear"

# 全state/labelが揃っているレスポンス
TEAM_ID="team-1"
MY_REVIEW_ID="s5"
WAITING_ID="s8"
SRC_MTG_ID="l6"
cat >"$tmp/full.json" <<EOF
{"data": {"teams": {"nodes": [{
  "id": "$TEAM_ID", "key": "NSY", "name": "Nsym",
  "states": {"nodes": [
    {"id": "s1", "name": "Triage"}, {"id": "s2", "name": "Todo"},
    {"id": "s3", "name": "AI Queued"}, {"id": "s4", "name": "AI Running"},
    {"id": "$MY_REVIEW_ID", "name": "My Review"}, {"id": "s6", "name": "Done"},
    {"id": "s7", "name": "In Progress"}, {"id": "$WAITING_ID", "name": "Waiting"}]},
  "labels": {"nodes": [
    {"id": "l3", "name": "src:jira"}, {"id": "l4", "name": "src:slack"},
    {"id": "l5", "name": "src:github"}, {"id": "$SRC_MTG_ID", "name": "src:mtg"},
    {"id": "l8", "name": "role:player"},
    {"id": "l9", "name": "role:manager"}, {"id": "l10", "name": "em:people"},
    {"id": "l11", "name": "em:tech"}, {"id": "l12", "name": "em:project"},
    {"id": "l13", "name": "em:product"}]}
}]}}}
EOF

# 1. 正常系: config.jsonが生成される
export CURL_RESPONSE="$tmp/full.json"
check "bootstrapが成功する" bash "$SCRIPT"
check "config.jsonが生成される" test -f "$tmp/config/linear/config.json"
check "team_idが入る" test "$(jq -r '.team_id' "$tmp/config/linear/config.json")" = "$TEAM_ID"
check "state 8件が入る" test "$(jq '.states | length' "$tmp/config/linear/config.json")" = "8"
check "label 10件が入る" test "$(jq '.labels | length' "$tmp/config/linear/config.json")" = "10"
check "My Reviewが入る" test "$(jq -r '.states["My Review"]' "$tmp/config/linear/config.json")" = "$MY_REVIEW_ID"
check "Waitingが入る" test "$(jq -r '.states["Waiting"]' "$tmp/config/linear/config.json")" = "$WAITING_ID"
check "src:mtgが入る" test "$(jq -r '.labels["src:mtg"]' "$tmp/config/linear/config.json")" = "$SRC_MTG_ID"
check "AI Reviewは残らない" test "$(jq -r '.states["AI Review"] // "null"' "$tmp/config/linear/config.json")" = "null"

# 2. state不足: 非0で失敗し、不足名を表示する
cat >"$tmp/missing.json" <<'EOF'
{"data": {"teams": {"nodes": [{
  "id": "team-1", "key": "NSY", "name": "Nsym",
  "states": {"nodes": [{"id": "s1", "name": "Triage"}, {"id": "s2", "name": "Todo"}]},
  "labels": {"nodes": []}
}]}}}
EOF
rm -f "$tmp/config/linear/config.json"
out=$(CURL_RESPONSE="$tmp/missing.json" bash "$SCRIPT" 2>&1)
check "state不足で非0" bash -c "export CURL_RESPONSE='$tmp/missing.json'; ! bash '$SCRIPT'"
check "不足state名を表示する" grep -q "AI Queued" <<<"$out"
check "不足時はconfig.jsonを書かない" test ! -f "$tmp/config/linear/config.json"

rm -rf "$tmp"
echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
