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

# stub claude: 実装してコミットするだけ。push/PR作成はスクリプト側の責務
cat > "$tmp/bin/claude" <<'EOF'
#!/bin/bash
echo "$*" >> "${CLAUDE_LOG:?}"
echo "implemented and committed"
EOF
chmod +x "$tmp/bin/claude"

# stub ghq / git（worktree操作をno-opに）
cat > "$tmp/bin/ghq" <<'EOF'
#!/bin/bash
[[ "$1" == "root" ]] && echo "${GHQ_ROOT:?}"
EOF
cat > "$tmp/bin/git" <<'EOF'
#!/bin/bash
echo "$*" >> "${GIT_LOG:?}"
# worktree add のときは実際にディレクトリを作る。
# 作らないと dispatch_one の `cd "$wt"` が失敗し、claude まで到達しない
if [[ "$*" == *"worktree add"* ]]; then
  for a in "$@"; do
    case "$a" in */.wt/*) mkdir -p "$a" ;; esac
  done
fi
# rev-list でコミット有無を判定している箇所に答える（GIT_COMMITS で件数を差し替える）
if [[ "$*" == *"rev-list"* ]]; then
  echo "${GIT_COMMITS:-2}"
fi
[[ "$*" == *"push"* && "${GIT_PUSH_FAIL:-0}" == "1" ]] && exit 1
exit 0
EOF
# stub gh: pr create でURLを返す
cat > "$tmp/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >> "${GH_LOG:?}"
# 事前チェック: PR作成権限の確認。GH_PERM で差し替える
if [[ "$*" == *"repo view"* ]]; then
  [[ "${GH_PERM_FAIL:-0}" == "1" ]] && { echo "gh: not found" >&2; exit 1; }
  echo "${GH_PERM:-ADMIN}"
  exit 0
fi
[[ "${GH_PR_FAIL:-0}" == "1" ]] && { echo "gh: pr create failed" >&2; exit 1; }
echo "https://github.com/example-org/repo1/pull/99"
EOF
chmod +x "$tmp/bin/ghq" "$tmp/bin/git" "$tmp/bin/gh"

export PATH="$tmp/bin:$PATH"
export CURL_LOG="$tmp/curl.log"
export CLAUDE_LOG="$tmp/claude.log"
export GIT_LOG="$tmp/git.log"
export GH_LOG="$tmp/gh.log"
export GHQ_ROOT="$tmp/ghq"
# CLAUDE_BINの既定は $HOME/.local/bin/claude。テストではPATH上のstubを使う
export CLAUDE_BIN="claude"
: > "$CURL_LOG"; : > "$CLAUDE_LOG"; : > "$GIT_LOG"; : > "$GH_LOG"

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

# 3. 正常系 → claude実行 → スクリプトがpush＋PR作成 → コメント＋判断待ちへ遷移
: > "$CURL_LOG"; : > "$CLAUDE_LOG"; : > "$GIT_LOG"; : > "$GH_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "claudeが実行される" test -s "$CLAUDE_LOG"
check "スクリプトがpushする" grep -q "push" "$GIT_LOG"
check "スクリプトがgh pr create --draftする" bash -c "grep -q 'pr create' '$GH_LOG' && grep -q -- '--draft' '$GH_LOG'"
check "PR URLがコメントされる" grep -q "pull/99" "$CURL_LOG"
check "判断待ち(s5)へ遷移する" bash -c "grep issueUpdate '$CURL_LOG' | grep -q '\"s5\"'"
check "プロンプトにLinear識別子を書かせない" grep -q "identifierを書かない\|NSY-xx" "$CLAUDE_LOG"
check "agentにpushさせない指示が入る" grep -q "pushしない\|push・PR作成はしない" "$CLAUDE_LOG"
check "agentのallowedToolsにgh/pushを渡さない" bash -c "! grep -qE 'Bash\\(gh:|git push' '$CLAUDE_LOG'"

# 3-2. コミットが無い → push/PRせずTodoへ差し戻す
: > "$CURL_LOG"; : > "$GIT_LOG"; : > "$GH_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  GIT_COMMITS=0 LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "コミット0件ならpushしない" bash -c "! grep -q 'push' '$GIT_LOG'"
check "コミット0件ならTodo(s2)へ差し戻す" grep -q '"s2"' "$CURL_LOG"

# 3-3. push失敗 → PR作成せずTodoへ差し戻す
: > "$CURL_LOG"; : > "$GIT_LOG"; : > "$GH_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  GIT_PUSH_FAIL=1 LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "push失敗ならPRを作らない" bash -c "! grep -q 'pr create' '$GH_LOG'"
check "push失敗ならTodo(s2)へ差し戻す" grep -q '"s2"' "$CURL_LOG"

# 3-4. PR作成失敗 → Todoへ差し戻す
: > "$CURL_LOG"; : > "$GIT_LOG"; : > "$GH_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  GH_PR_FAIL=1 LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "PR作成失敗ならTodo(s2)へ差し戻す" grep -q '"s2"' "$CURL_LOG"

# 3-5. PR作成権限が無い → agentを走らせる前に弾く
: > "$CURL_LOG"; : > "$CLAUDE_LOG"; : > "$GIT_LOG"; : > "$GH_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  GH_PERM=READ LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "権限不足ならclaudeを実行しない" test ! -s "$CLAUDE_LOG"
check "権限不足ならworktreeも作らない" bash -c "! grep -q 'worktree add' '$GIT_LOG'"
check "権限不足ならTodo(s2)へ差し戻す" grep -q '"s2"' "$CURL_LOG"

# 3-6. 権限確認そのものが失敗 → 判定不能なので実行しない（安全側に倒す）
: > "$CURL_LOG"; : > "$CLAUDE_LOG"; : > "$GIT_LOG"; : > "$GH_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  GH_PERM_FAIL=1 LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "権限確認が失敗したらclaudeを実行しない" test ! -s "$CLAUDE_LOG"

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
