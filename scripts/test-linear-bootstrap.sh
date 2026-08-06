#!/bin/bash
# linear-bootstrap.sh のテスト
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/linear-bootstrap.sh"
pass=0; fail=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok: $desc"; pass=$((pass+1))
  else echo "NG: $desc"; fail=$((fail+1)); fi
}

tmp=$(mktemp -d)
mkdir -p "$tmp/config/linear" "$tmp/bin"
echo "lin_api_test" > "$tmp/config/linear/api-key"

cat > "$tmp/bin/curl" <<'EOF'
#!/bin/bash
cat "${CURL_RESPONSE:?}"
EOF
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
export LINEAR_CONFIG_DIR="$tmp/config/linear"

# 全state/labelが揃っているレスポンス
cat > "$tmp/full.json" <<'EOF'
{"data": {"teams": {"nodes": [{
  "id": "team-1", "key": "NSY", "name": "Nsym",
  "states": {"nodes": [
    {"id": "s1", "name": "Triage"}, {"id": "s2", "name": "Todo"},
    {"id": "s3", "name": "AI Ready"}, {"id": "s4", "name": "AI Running"},
    {"id": "s5", "name": "判断待ち"}, {"id": "s6", "name": "Done"}]},
  "labels": {"nodes": [
    {"id": "l1", "name": "ai:ready"}, {"id": "l2", "name": "ai:blocked-human"},
    {"id": "l3", "name": "src:jira"}, {"id": "l4", "name": "src:slack"},
    {"id": "l5", "name": "src:github"}, {"id": "l6", "name": "src:esa"},
    {"id": "l7", "name": "src:todoist"}, {"id": "l8", "name": "role:player"},
    {"id": "l9", "name": "role:manager"}, {"id": "l10", "name": "em:people"},
    {"id": "l11", "name": "em:tech"}, {"id": "l12", "name": "em:project"},
    {"id": "l13", "name": "em:product"}]}
}]}}}
EOF

# 1. 正常系: config.jsonが生成される
export CURL_RESPONSE="$tmp/full.json"
check "bootstrapが成功する" bash "$SCRIPT"
check "config.jsonが生成される" test -f "$tmp/config/linear/config.json"
check "team_idが入る" test "$(jq -r '.team_id' "$tmp/config/linear/config.json")" = "team-1"
check "state 6件が入る" test "$(jq '.states | length' "$tmp/config/linear/config.json")" = "6"
check "label 13件が入る" test "$(jq '.labels | length' "$tmp/config/linear/config.json")" = "13"

# 2. state不足: 非0で失敗し、不足名を表示する
cat > "$tmp/missing.json" <<'EOF'
{"data": {"teams": {"nodes": [{
  "id": "team-1", "key": "NSY", "name": "Nsym",
  "states": {"nodes": [{"id": "s1", "name": "Triage"}, {"id": "s2", "name": "Todo"}]},
  "labels": {"nodes": []}
}]}}}
EOF
rm -f "$tmp/config/linear/config.json"
out=$(CURL_RESPONSE="$tmp/missing.json" bash "$SCRIPT" 2>&1)
check "state不足で非0" bash -c "export CURL_RESPONSE='$tmp/missing.json'; ! bash '$SCRIPT'"
check "不足state名を表示する" grep -q "AI Ready" <<<"$out"
check "不足時はconfig.jsonを書かない" test ! -f "$tmp/config/linear/config.json"

rm -rf "$tmp"
echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
