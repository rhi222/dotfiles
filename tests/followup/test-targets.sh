#!/bin/bash
# followup targets.sh のテスト
# Linearの未完了issueだけを取り、そのまま dotctl followup targets へ渡す。
# Linearが失敗したら dotctl を呼ばない（空の対象で targets.json を上書きしない）。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/followup/targets.sh"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
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

mkdir -p "$TMP/linear" "$TMP/bin"
echo "lin_api_test" >"$TMP/linear/api-key"
echo '{"team_id": "team-1"}' >"$TMP/linear/config.json"
cat >"$TMP/bin/curl" <<'EOF'
#!/bin/bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--data" ]]; then echo "$2" >>"${CURL_LOG:?}"; shift 2; else shift; fi
done
cat "${CURL_RESPONSE:?}"
EOF
cat >"$TMP/bin/dotctl" <<'EOF'
#!/bin/bash
echo "ARGS $*" >>"${DOTCTL_LOG:?}"
cat >>"$DOTCTL_LOG"
echo '[{"key":"k"}]'
EOF
chmod +x "$TMP/bin/curl" "$TMP/bin/dotctl"
export PATH="$TMP/bin:$PATH" LINEAR_CONFIG_DIR="$TMP/linear" CURL_LOG="$TMP/curl.log" DOTCTL_LOG="$TMP/dotctl.log"

# 1. 成功: issuesの配列をdotctlへ渡し、その出力を返す
echo '{"data":{"issues":{"nodes":[{"identifier":"NSY-1","title":"t","url":"u","description":"d"}]}}}' >"$TMP/ok.json"
out=$(CURL_RESPONSE="$TMP/ok.json" bash "$SCRIPT")
check "dotctlの出力をそのまま返す" test "$out" = '[{"key":"k"}]'
check "dotctl followup targets --in - を呼ぶ" grep -q "ARGS followup targets --in -" "$TMP/dotctl.log"
check "issuesの配列だけを渡す" grep -q '"identifier": "NSY-1"' "$TMP/dotctl.log"
check "teamで絞る" grep -q '"team":"team-1"' "$CURL_LOG"
check "完了・取消・重複を除く" grep -q 'completed' "$CURL_LOG"

# 2. GraphQLエラー: dotctlを呼ばずに非0
rm -f "$TMP/dotctl.log"
echo '{"errors":[{"message":"boom"}]}' >"$TMP/ng.json"
CURL_RESPONSE="$TMP/ng.json" bash "$SCRIPT" >/dev/null 2>&1
check "Linear失敗で非0" test $? -ne 0
check "Linear失敗でdotctlを呼ばない" test ! -e "$TMP/dotctl.log"

# 3. data.issues が null（errorsなし）: dotctlを呼ばずに非0
rm -f "$TMP/dotctl.log"
echo '{"data":{"issues":null}}' >"$TMP/null.json"
CURL_RESPONSE="$TMP/null.json" bash "$SCRIPT" >/dev/null 2>&1
check "nullで非0" test $? -ne 0
check "nullでdotctlを呼ばない" test ! -e "$TMP/dotctl.log"

echo "---"
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
