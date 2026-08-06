#!/bin/bash
# linear-dispatch-cron.sh のテスト。curl/claude/ghq/gitをstubにする
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/linear-dispatch-cron.sh"
pass=0; fail=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok: $desc"; pass=$((pass+1))
  else echo "NG: $desc"; fail=$((fail+1)); fi
}

tmp=$(mktemp -d)
mkdir -p "$tmp/home/.config/linear" "$tmp/bin" "$tmp/ghq/github.com/example-org/repo1"
echo "lin_api_test" > "$tmp/home/.config/linear/api-key"
cat > "$tmp/home/.config/linear/config.json" <<'EOF'
{"team_id": "t1",
 "states": {"Triage": "s1", "Todo": "s2", "AI Ready": "s3", "AI Running": "s4", "判断待ち": "s5", "Done": "s6"},
 "labels": {"ai:ready": "l1", "ai:blocked-human": "l2", "src:jira": "l3", "src:slack": "l4", "src:github": "l5", "src:esa": "l6"}}
EOF

# --- 関数単体テスト（sourceして呼ぶ） ---
export LINEAR_CONFIG_DIR="$tmp/home/.config/linear"
source "$SCRIPT"
set +eo pipefail  # スクリプト側の set -euo pipefail をテストシェルへ持ち込まない

desc_ok=$'調査タスク\nrepo: github.com/example-org/repo1\n期待アウトカム: x'
check "repo行をパースできる" test "$(dispatch_parse_repo "$desc_ok")" = "github.com/example-org/repo1"
check "repo行が無ければ非0" bash -c "source '$SCRIPT'; ! dispatch_parse_repo 'repo指定なし本文'"

# Linearは github.com/... を自動でmarkdownリンク化するため、その形式も解釈できること
desc_md=$'repo: [github.com/rhi222/dotfiles](<http://github.com/rhi222/dotfiles>)\n期待アウトカム: x'
check "markdownリンク化されたrepo行もパースできる" test "$(dispatch_parse_repo "$desc_md")" = "github.com/rhi222/dotfiles"

log_ok=$'作業した\nPR_URL: https://github.com/example-org/repo1/pull/99'
check "PR URLをパースできる" test "$(dispatch_parse_pr_url "$log_ok")" = "https://github.com/example-org/repo1/pull/99"
check "PR URLが無ければ非0" bash -c "source '$SCRIPT'; ! dispatch_parse_pr_url 'URLなしログ'"

# --- スクリプト全体のテスト ---
# stub curl: リクエスト内容で応答を出し分ける
cat > "$tmp/bin/curl" <<'EOF'
#!/bin/bash
data=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--data" ]]; then data="$2"; echo "$2" >> "${CURL_LOG:?}"; shift 2; else shift; fi
done
if grep -q 'viewer' <<<"$data"; then
  echo '{"data": {"viewer": {"id": "user-me"}}}'
elif grep -q '\\"s5\\"' <<<"$data" || grep -q '"s5"' <<<"$data"; then
  cat "${WIP_RESPONSE:?}"        # 判断待ち一覧（WIPチェック用）
elif grep -q 'issues(' <<<"$data"; then
  cat "${READY_RESPONSE:?}"      # AI Ready一覧
elif grep -q 'issueUpdate' <<<"$data"; then
  echo '{"data": {"issueUpdate": {"success": true}}}'
else
  echo '{"data": {"commentCreate": {"success": true}}}'
fi
EOF
chmod +x "$tmp/bin/curl"

# stub claude: PR_URL行を出す成功パターン
cat > "$tmp/bin/claude" <<'EOF'
#!/bin/bash
echo "$*" >> "${CLAUDE_LOG:?}"
echo "implemented"
echo "PR_URL: https://github.com/example-org/repo1/pull/99"
EOF
chmod +x "$tmp/bin/claude"

# stub ghq / git（worktree操作をno-opに）
cat > "$tmp/bin/ghq" <<'EOF'
#!/bin/bash
[[ "$1" == "root" ]] && echo "${GHQ_ROOT:?}"
EOF
cat > "$tmp/bin/git" <<'EOF'
#!/bin/bash
# worktree add のときは実際にディレクトリを作る。
# 作らないと dispatch_one の `cd "$wt"` が失敗し、claude まで到達しない
if [[ "$*" == *"worktree add"* ]]; then
  for a in "$@"; do
    case "$a" in */.wt/*) mkdir -p "$a" ;; esac
  done
fi
exit 0
EOF
chmod +x "$tmp/bin/ghq" "$tmp/bin/git"

export PATH="$tmp/bin:$PATH"
export CURL_LOG="$tmp/curl.log"
export CLAUDE_LOG="$tmp/claude.log"
export GHQ_ROOT="$tmp/ghq"
# CLAUDE_BINの既定は $HOME/.local/bin/claude。テストではPATH上のstubを使う
export CLAUDE_BIN="claude"
: > "$CURL_LOG"; : > "$CLAUDE_LOG"

echo '{"data": {"issues": {"nodes": []}}}' > "$tmp/wip-empty.json"
echo '{"data": {"issues": {"nodes": [{"id": "i1", "identifier": "NSY-5", "title": "調査", "description": "repo: github.com/example-org/repo1\n期待アウトカム: x", "url": "u"}]}}}' > "$tmp/ready-one.json"
echo '{"data": {"issues": {"nodes": [{"id": "i2", "identifier": "NSY-6", "title": "repo無し", "description": "repo行がない本文", "url": "u"}]}}}' > "$tmp/ready-norepo.json"
jq -n '{data: {issues: {nodes: [range(10) | {id: "i\(.)", identifier: "NSY-\(.)", title: "t", description: "", url: "u"}]}}}' > "$tmp/wip-full.json"

# 1. フラグなし → 静かにスキップ
out1=$(HOME="$tmp/home" bash "$SCRIPT" 2>&1)
check "フラグなしで静かにスキップ" test -z "$out1"

touch "$tmp/home/.config/linear-dispatch-enabled"

# 2. WIP上限超過 → ディスパッチしない
out2=$(HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-full.json" READY_RESPONSE="$tmp/ready-one.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" 2>&1)
check "WIP上限超過でスキップする" grep -q "WIP" <<<"$out2"
check "WIP超過時はclaudeを実行しない" test ! -s "$CLAUDE_LOG"

# 3. 正常系 → claude実行後、PR URLコメント＋判断待ちへ遷移
: > "$CURL_LOG"; : > "$CLAUDE_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "claudeが実行される" test -s "$CLAUDE_LOG"
check "PR URLがコメントされる" grep -q "pull/99" "$CURL_LOG"
check "判断待ち(s5)へ遷移する" bash -c "grep issueUpdate '$CURL_LOG' | grep -q '\"s5\"'"
check "プロンプトにLinear識別子を書かせない" grep -q "identifierを書かない\|NSY-xx" "$CLAUDE_LOG"

# 4. repo行が無い → claudeを実行せずTodoへ差し戻し
: > "$CURL_LOG"; : > "$CLAUDE_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-norepo.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "repo行が無ければclaudeを実行しない" test ! -s "$CLAUDE_LOG"
check "repo行が無ければTodo(s2)へ差し戻す" grep -q '"s2"' "$CURL_LOG"

# 5. claude失敗 → エラーコメント＋Todoへ差し戻し
cat > "$tmp/bin/claude" <<'EOF'
#!/bin/bash
echo "$*" >> "${CLAUDE_LOG:?}"
echo "something went wrong" >&2
exit 1
EOF
chmod +x "$tmp/bin/claude"
: > "$CURL_LOG"; : > "$CLAUDE_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "失敗時はTodo(s2)へ差し戻す" grep -q '"s2"' "$CURL_LOG"
check "失敗ログがコメントされる" grep -q "went wrong" "$CURL_LOG"

[[ "${KEEP_TMP:-0}" == "1" ]] && echo "tmp: $tmp" || rm -rf "$tmp"
echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
