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
 "labels": {"src:github": "lb-gh", "src:jira": "lb-jira", "ai:ready": "lb-r", "ai:blocked-human": "lb-b", "src:slack": "lb-s", "src:esa": "lb-e", "src:todoist": "lb-t", "role:player": "lb-rp", "role:manager": "lb-rm", "em:people": "lb-ep", "em:tech": "lb-et", "em:project": "lb-epj", "em:product": "lb-epd"}}
EOF

# stub gh: 呼び出しを記録し、search 以外（書き込み系）が来たら異常終了する
cat > "$tmp/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >> "${GH_LOG:?}"
case "$1" in
  search|api|auth) ;;
  *) echo "gh stub: 書き込み系サブコマンドが呼ばれた: $1" >&2; exit 99 ;;
esac
echo '[{"url": "https://github.com/example-org/repo1/pull/1", "title": "PR one"},
      {"url": "https://github.com/example-org/repo2/pull/2", "title": "PR two"}]'
EOF
chmod +x "$tmp/bin/gh"

# stub curl: issueCreate成功を返し、payloadと引数を記録
cat > "$tmp/bin/curl" <<'EOF'
#!/bin/bash
echo "ARGS: $*" >> "${CURL_LOG:?}"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--data" ]]; then echo "$2" >> "${CURL_LOG:?}"; shift 2; else shift; fi
done
echo '{"data": {"issueCreate": {"success": true, "issue": {"id": "i1", "identifier": "NSY-9", "url": "u"}}}}'
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

# 3. 再実行 → seen済みは起票しない（冪等）
: > "$CURL_LOG"
HOME="$tmp/home" LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "2回目はissueCreateを呼ばない" bash -c "! grep -q issueCreate '$CURL_LOG'"

# 4. jira.envなし → Jiraはスキップ（エラーにならない）
check "jira.env無しでも正常終了" test -f "$seen"

# 5. 外部システムへの書き戻しをしない（read-onlyの強制）
check "ghはsearchしか呼ばない" bash -c "! grep -qvE '^(search|api|auth) ' '$GH_LOG'"
check "gh issue commentを呼ばない" bash -c "! grep -q 'issue comment' '$GH_LOG'"
check "gh pr commentを呼ばない" bash -c "! grep -q 'pr comment' '$GH_LOG'"
check "gh pr editを呼ばない" bash -c "! grep -q 'pr edit' '$GH_LOG'"
check "curlはLinear宛のみ（Jira等へPOSTしない）" bash -c "! grep -E '^ARGS:' '$GH_LOG' >/dev/null; ! grep -E '^ARGS:.*atlassian' '$CURL_LOG'"

rm -rf "$tmp"
echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
