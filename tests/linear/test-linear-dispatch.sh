#!/bin/bash
# dispatchは権限・WIP・成果を確認してからpushとdraft PRを行い、失敗時は安全なstateへ戻す。
# curl/claude/ghq/gitをstubにし、実repositoryや共有systemは変更しない。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
SCRIPT="$SCRIPTS_DIR/linear/dispatch-cron.sh"
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
mkdir -p "$tmp/home/.config/linear" "$tmp/bin" "$tmp/ghq/github.com/example-org/repo1"
echo "lin_api_test" >"$tmp/home/.config/linear/api-key"
# fixture とアサーションで同じ state ID を別々に書かない（単一ソース）。
# 下の config.json（heredoc 展開で埋め込む）・curl スタブ（実行時に env 経由で読む）・
# アサーション（テストシェルで直接参照）の3箇所が、この定義だけを参照する。
export STATE_TRIAGE="s1" STATE_TODO="s2" STATE_AI_QUEUED="s3" STATE_AI_RUNNING="s4"
export STATE_MY_REVIEW="s5" STATE_DONE="s6" STATE_IN_PROGRESS="s7" STATE_WAITING="s8"
cat >"$tmp/home/.config/linear/config.json" <<EOF
{"team_id": "t1",
 "states": {"Triage": "$STATE_TRIAGE", "Todo": "$STATE_TODO", "AI Queued": "$STATE_AI_QUEUED", "AI Running": "$STATE_AI_RUNNING", "My Review": "$STATE_MY_REVIEW", "Done": "$STATE_DONE", "In Progress": "$STATE_IN_PROGRESS", "Waiting": "$STATE_WAITING"},
 "labels": {"src:jira": "l3", "src:slack": "l4", "src:github": "l5", "src:mtg": "l6"}}
EOF

# --- 関数単体テスト（sourceして呼ぶ） ---
export LINEAR_CONFIG_DIR="$tmp/home/.config/linear"
# shellcheck source=/dev/null  # 検査対象のパスは実行時に決まる
source "$SCRIPT"
set +eo pipefail # スクリプト側の set -euo pipefail をテストシェルへ持ち込まない

desc_ok=$'調査タスク\nrepo: github.com/example-org/repo1\n期待アウトカム: x'
check "repo行をパースできる" test "$(dispatch_parse_repo "$desc_ok")" = "github.com/example-org/repo1"
check "repo行が無ければ非0" bash -c "source '$SCRIPT'; ! dispatch_parse_repo 'repo指定なし本文'"

# dispatch_parse_pr_url は本文からPR参照を拾う（モード判定の分岐点）。
# 素のURLとmarkdownリンクの両方で同じ結果になること
desc_pr=$'draft仕上げ\n元URL: https://github.com/example-org/repo1/pull/42'
check "本文のPR URLをパースできる" test "$(dispatch_parse_pr_url "$desc_pr")" = "example-org/repo1/42"
check "PR URLが無ければ非0" bash -c "source '$SCRIPT'; ! dispatch_parse_pr_url 'PR URLなし本文'"

# --- スクリプト全体のテスト ---
# stub curl: リクエスト内容で応答を出し分ける
cat >"$tmp/bin/curl" <<'EOF'
#!/bin/bash
data=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--data" ]]; then data="$2"; echo "$2" >> "${CURL_LOG:?}"; shift 2; else shift; fi
done
if grep -q 'viewer' <<<"$data"; then
  echo '{"data": {"viewer": {"id": "user-me"}}}'
elif grep -q "\\\\\"${STATE_MY_REVIEW:?}\\\\\"" <<<"$data" || grep -q "\"${STATE_MY_REVIEW:?}\"" <<<"$data"; then
  cat "${WIP_RESPONSE:?}"        # My Review一覧（WIPチェック用）
elif grep -q 'issues(' <<<"$data"; then
  cat "${READY_RESPONSE:?}"      # AI Queued一覧
elif grep -q 'issueUpdate' <<<"$data"; then
  # MOVE_FAIL_ONCE を指すファイルがあれば、最初の state 遷移だけ失敗させる。
  # 1件目のAPIが一時失敗したときに2件目以降が処理されるかを見るため
  if [[ -n "${MOVE_FAIL_ONCE:-}" ]]; then
    n=$(cat "$MOVE_FAIL_ONCE" 2>/dev/null || echo 0)
    if [[ "$n" == "0" ]]; then
      echo 1 >"$MOVE_FAIL_ONCE"
      echo '{"errors": [{"message": "rate limited"}]}'
      exit 0
    fi
  fi
  echo '{"data": {"issueUpdate": {"success": true}}}'
else
  echo '{"data": {"commentCreate": {"success": true}}}'
fi
EOF
chmod +x "$tmp/bin/curl"

# stub claude: 実装してコミットするだけ。push/PR作成はスクリプト側の責務
cat >"$tmp/bin/claude" <<'EOF'
#!/bin/bash
echo "$*" >> "${CLAUDE_LOG:?}"
# コミットを積んだことにする（HEADが進む）。CLAUDE_NO_COMMIT=1 なら積まない
[[ "${CLAUDE_NO_COMMIT:-0}" == "1" ]] || echo "after-$RANDOM" > "${HEAD_FILE:?}"
echo "implemented and committed"
EOF
chmod +x "$tmp/bin/claude"

# stub ghq / git（worktree操作をno-opに）
cat >"$tmp/bin/ghq" <<'EOF'
#!/bin/bash
[[ "$1" == "root" ]] && echo "${GHQ_ROOT:?}"
EOF
# git stub は worktree / branch の登録簿（GIT_WT_REG / GIT_BR_REG）を持ち、
# 実際の git のように「新規ブランチが既存なら worktree add が失敗する」
# 「worktree list / show-ref / branch -D が登録簿を反映する」を模す。
# これで掃除ロジック（残骸掃除・成功時掃除）を実挙動で検証できる
cat >"$tmp/bin/git" <<'EOF'
#!/bin/bash
echo "$*" >> "${GIT_LOG:?}"
BR_REG="${GIT_BR_REG:?}"
WT_REG="${GIT_WT_REG:?}"
touch "$BR_REG" "$WT_REG"
argv=("$@")

if [[ "$*" == *"worktree add"* ]]; then
  wt=""; br=""; newbranch=0
  for ((i = 0; i < ${#argv[@]}; i++)); do
    case "${argv[i]}" in
      */.wt/*) wt="${argv[i]}" ;;
      -b) newbranch=1; br="${argv[i + 1]}" ;;
    esac
  done
  if [[ $newbranch -eq 1 ]]; then
    # 新規ブランチ: 既に存在すれば git 同様に失敗する（掃除しないと詰まる経路）
    if grep -qxF "$br" "$BR_REG"; then
      echo "fatal: a branch named '$br' already exists" >&2
      exit 128
    fi
    echo "$br" >>"$BR_REG"
  else
    # 継続モード: パス直後の位置引数が既存ブランチ
    for ((i = 0; i < ${#argv[@]}; i++)); do
      [[ "${argv[i]}" == "$wt" ]] && br="${argv[i + 1]}"
    done
  fi
  # dispatch_one の `cd "$wt"` が通るよう実際にディレクトリを作る
  mkdir -p "$wt"
  echo "$wt $br" >>"$WT_REG"
  exit 0
fi

if [[ "$*" == *"worktree remove"* ]]; then
  wt=""
  for a in "$@"; do case "$a" in */.wt/*) wt="$a" ;; esac; done
  grep -vF "$wt " "$WT_REG" >"$WT_REG.tmp" 2>/dev/null || true
  mv "$WT_REG.tmp" "$WT_REG"
  rm -rf "$wt"
  exit 0
fi

if [[ "$*" == *"worktree list"* ]]; then
  while read -r wt br; do
    [[ -n "$wt" ]] || continue
    echo "worktree $wt"
    [[ -n "$br" ]] && echo "branch refs/heads/$br"
    echo ""
  done <"$WT_REG"
  exit 0
fi

# show-ref --verify refs/heads/<branch> でブランチ存在を判定
if [[ "$*" == *"show-ref"* ]]; then
  br=""
  for a in "$@"; do case "$a" in refs/heads/*) br="${a#refs/heads/}" ;; esac; done
  grep -qxF "$br" "$BR_REG" && exit 0 || exit 1
fi

if [[ "$*" == *"branch -D"* ]]; then
  br="${argv[-1]}"
  grep -vxF "$br" "$BR_REG" >"$BR_REG.tmp" 2>/dev/null || true
  mv "$BR_REG.tmp" "$BR_REG"
  exit 0
fi

# コミット有無は rev-parse HEAD の前後比較で判定される。
# claude stub が HEAD_FILE を書き換えることで「コミットが積まれた」を模す
if [[ "$*" == *"rev-parse HEAD"* ]]; then
  cat "${HEAD_FILE:?}" 2>/dev/null || echo "base"
  exit 0
fi

[[ "$*" == *"push"* && "${GIT_PUSH_FAIL:-0}" == "1" ]] && exit 1
exit 0
EOF
# stub gh: pr create でURLを返す
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >> "${GH_LOG:?}"
# 継続モード: 既存PRのブランチと状態を返す
if [[ "$*" == *"pr view"* ]]; then
  echo "{\"headRefName\": \"${GH_PR_BRANCH:-feat/existing}\", \"state\": \"${GH_PR_STATE:-OPEN}\", \"url\": \"https://github.com/example-org/repo1/pull/42\"}"
  exit 0
fi
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
export HEAD_FILE="$tmp/head"
echo "base" >"$HEAD_FILE"
export GH_LOG="$tmp/gh.log"
export GHQ_ROOT="$tmp/ghq"
# git stub の worktree / branch 登録簿
export GIT_BR_REG="$tmp/git-branches"
export GIT_WT_REG="$tmp/git-worktrees"
: >"$GIT_BR_REG"
: >"$GIT_WT_REG"
# CLAUDE_BINの既定は $HOME/.local/bin/claude。テストではPATH上のstubを使う
export CLAUDE_BIN="claude"
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
echo base >"$HEAD_FILE"

echo '{"data": {"issues": {"nodes": []}}}' >"$tmp/wip-empty.json"
# shellcheck disable=SC2028  # \n はJSON文字列内のエスケープ。シェルで展開させたくない
echo '{"data": {"issues": {"nodes": [{"id": "i1", "identifier": "NSY-5", "title": "調査", "description": "repo: github.com/example-org/repo1\n期待アウトカム: x", "url": "u"}]}}}' >"$tmp/ready-one.json"
echo '{"data": {"issues": {"nodes": [{"id": "i2", "identifier": "NSY-6", "title": "repo無し", "description": "repo行がない本文", "url": "u"}]}}}' >"$tmp/ready-norepo.json"
# 継続モード: 本文に既存PRのURLがある
echo '{"data": {"issues": {"nodes": [{"id": "i3", "identifier": "NSY-7", "title": "draft仕上げ: 既存PRの続き", "description": "元URL: https://github.com/example-org/repo1/pull/42", "url": "u"}]}}}' >"$tmp/ready-existing-pr.json"
jq -n '{data: {issues: {nodes: [range(10) | {id: "i\(.)", identifier: "NSY-\(.)", title: "t", description: "", url: "u"}]}}}' >"$tmp/wip-full.json"
# 2件を続けて処理させる。1件目のAPIが失敗しても2件目が落ちないことの確認用
jq -n '{data: {issues: {nodes: [
  {id: "ia", identifier: "NSY-11", title: "1件目", description: "repo: github.com/example-org/repo1", url: "u"},
  {id: "ib", identifier: "NSY-12", title: "2件目", description: "repo: github.com/example-org/repo1", url: "u"}
]}}}' >"$tmp/ready-two.json"

# 1. フラグなし → 静かにスキップ
out1=$(HOME="$tmp/home" bash "$SCRIPT" 2>&1)
check "フラグなしで静かにスキップ" test -z "$out1"

touch "$tmp/home/.config/linear-dispatch-enabled"

# 2. WIP上限超過 → ディスパッチしない
out2=$(HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-full.json" READY_RESPONSE="$tmp/ready-one.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" 2>&1)
check "WIP上限超過でスキップする" grep -q "WIP" <<<"$out2"
check "WIP超過時はclaudeを実行しない" test ! -s "$CLAUDE_LOG"

# 3. 正常系 → claude実行 → スクリプトがpush＋PR作成 → コメント＋My Reviewへ遷移
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
echo base >"$HEAD_FILE"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "claudeが実行される" test -s "$CLAUDE_LOG"
check "スクリプトがpushする" grep -q "push" "$GIT_LOG"
check "スクリプトがgh pr create --draftする" bash -c "grep -q 'pr create' '$GH_LOG' && grep -q -- '--draft' '$GH_LOG'"
check "PR URLがコメントされる" grep -q "pull/99" "$CURL_LOG"
check "My Review(s5)へ遷移する" bash -c "grep issueUpdate '$CURL_LOG' | grep -q '\"$STATE_MY_REVIEW\"'"
check "プロンプトにLinear識別子を書かせない" grep -q "identifierを書かない\|NSY-xx" "$CLAUDE_LOG"
check "agentにpushさせない指示が入る" grep -q "pushしない\|push・PR作成はしない" "$CLAUDE_LOG"
check "agentのallowedToolsにgh/pushを渡さない" bash -c "! grep -qE 'Bash\\(gh:|git push' '$CLAUDE_LOG'"

# 3-2. コミットが無い → push/PRせずTodoへ差し戻す
: >"$CURL_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  CLAUDE_NO_COMMIT=1 LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "コミット0件ならpushしない" bash -c "! grep -q 'push' '$GIT_LOG'"
check "コミット0件ならTodo(s2)へ差し戻す" grep -q "\"$STATE_TODO\"" "$CURL_LOG"

# 3-3. push失敗 → PR作成せずTodoへ差し戻す
: >"$CURL_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  GIT_PUSH_FAIL=1 LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "push失敗ならPRを作らない" bash -c "! grep -q 'pr create' '$GH_LOG'"
check "push失敗ならTodo(s2)へ差し戻す" grep -q "\"$STATE_TODO\"" "$CURL_LOG"
check "push失敗コメントにブランチ名が入る" grep -q 'linear/NSY-5' "$CURL_LOG"

# 3-4. PR作成失敗 → Todoへ差し戻す
: >"$CURL_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  GH_PR_FAIL=1 LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "PR作成失敗ならTodo(s2)へ差し戻す" grep -q "\"$STATE_TODO\"" "$CURL_LOG"

# 3-7. 継続モード: 本文にPR URLがあれば既存ブランチで作業し、新規PRを作らない
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
echo base >"$HEAD_FILE"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-existing-pr.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "継続モードでclaudeが実行される" test -s "$CLAUDE_LOG"
check "継続モードは既存ブランチでworktreeを作る" grep -q "feat/existing" "$GIT_LOG"
check "継続モードはlinear/NSY-7ブランチを作らない" bash -c "! grep -q 'linear/NSY-7' '$GIT_LOG'"
check "継続モードもpushする" grep -q "push" "$GIT_LOG"
check "継続モードは新規PRを作らない" bash -c "! grep -q 'pr create' '$GH_LOG'"
check "継続モードは既存PR URLをコメントする" grep -q "pull/42" "$CURL_LOG"
check "継続モードもMy Review(s5)へ遷移する" bash -c "grep issueUpdate '$CURL_LOG' | grep -q '\"$STATE_MY_REVIEW\"'"

# 3-8. 継続モード: PRがOPENでなければ実行しない
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
echo base >"$HEAD_FILE"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-existing-pr.json" \
  GH_PR_STATE=MERGED LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "PRがOPENでなければclaudeを実行しない" test ! -s "$CLAUDE_LOG"
check "PRがOPENでなければTodo(s2)へ差し戻す" grep -q "\"$STATE_TODO\"" "$CURL_LOG"

# 3-5. PR作成権限が無い → agentを走らせる前に弾く
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
echo base >"$HEAD_FILE"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  GH_PERM=READ LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "権限不足ならclaudeを実行しない" test ! -s "$CLAUDE_LOG"
check "権限不足ならworktreeも作らない" bash -c "! grep -q 'worktree add' '$GIT_LOG'"
check "権限不足ならTodo(s2)へ差し戻す" grep -q "\"$STATE_TODO\"" "$CURL_LOG"

# 3-6. 権限確認そのものが失敗 → 判定不能なので実行しない（安全側に倒す）
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
echo base >"$HEAD_FILE"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  GH_PERM_FAIL=1 LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "権限確認が失敗したらclaudeを実行しない" test ! -s "$CLAUDE_LOG"

# 3-9. 1件目のAPIが一時失敗しても2件目の処理は続ける。
# 夜間バッチなので、1件の rate limit で残り全部が落ちると朝まで気付けない
cat >"$tmp/bin/claude" <<'EOF'
#!/bin/bash
echo "$*" >> "${CLAUDE_LOG:?}"
[[ "${CLAUDE_NO_COMMIT:-0}" == "1" ]] || echo "after-$RANDOM" > "${HEAD_FILE:?}"
echo "implemented and committed"
EOF
chmod +x "$tmp/bin/claude"
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
echo base >"$HEAD_FILE"
echo 0 >"$tmp/move-fail-once"
out39=$(HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-two.json" \
  MOVE_FAIL_ONCE="$tmp/move-fail-once" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" 2>&1)
# APIペイロードに出るのは identifier ではなく issue id。2件目は "ib"
check "1件目のAPI失敗で2件目も処理される" grep -q '"ib"' "$CURL_LOG"
check "1件目は着手せずスキップする" grep -q "NSY-11: SKIPPED" <<<"$out39"
check "2件目はclaudeまで到達する" grep -q "夜間dispatch完了" "$CURL_LOG"

# 3-10. 成功時: push/PR後にworktreeとブランチを掃除する。
# pushでリモートに上がっているのでローカルworktreeを残す意味が薄い
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
: >"$GIT_BR_REG"
: >"$GIT_WT_REG"
echo base >"$HEAD_FILE"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "成功時にworktreeを掃除する" grep -q "worktree remove" "$GIT_LOG"
check "成功時(new)にブランチを削除する" grep -q "branch -D linear/NSY-5" "$GIT_LOG"

# 3-11. 失敗後の残骸（worktree + linear/<id>ブランチ）があっても、再実行で
# BOUNCED にならず掃除して着手できる（恒久BOUNCEDの回帰防止）。
# 掃除が無いと worktree add がブランチ既存で失敗し、永遠に BOUNCED になる
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
: >"$GIT_BR_REG"
: >"$GIT_WT_REG"
stale_wt="$tmp/ghq/github.com/example-org/repo1/.wt/linear-NSY-5"
mkdir -p "$stale_wt"
echo "linear/NSY-5" >"$GIT_BR_REG"
echo "$stale_wt linear/NSY-5" >"$GIT_WT_REG"
echo base >"$HEAD_FILE"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >"$tmp/out311.txt" 2>&1
check "残骸があっても再実行でBOUNCEDにならない" bash -c "! grep -q 'BOUNCED' '$tmp/out311.txt'"
check "残骸掃除後に正常完了する（OK）" grep -q "NSY-5: OK" "$tmp/out311.txt"
check "残骸を掃除してclaudeまで到達する" test -s "$CLAUDE_LOG"
check "残骸のブランチを削除してからworktreeを作り直す" grep -q "branch -D linear/NSY-5" "$GIT_LOG"

# 3-12. 継続モードの成功時: worktreeは掃除するが既存PRブランチは消さない
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
: >"$GIT_LOG"
: >"$GH_LOG"
: >"$GIT_BR_REG"
: >"$GIT_WT_REG"
echo base >"$HEAD_FILE"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-existing-pr.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "継続モードの成功時もworktreeを掃除する" grep -q "worktree remove" "$GIT_LOG"
check "継続モードの成功時は既存PRブランチを削除しない" bash -c "! grep -q 'branch -D' '$GIT_LOG'"

# 4. repo行が無い → claudeを実行せずTodoへ差し戻し
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-norepo.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "repo行が無ければclaudeを実行しない" test ! -s "$CLAUDE_LOG"
check "repo行が無ければTodo(s2)へ差し戻す" grep -q "\"$STATE_TODO\"" "$CURL_LOG"

# 4-2. repo行が無くても role:manager ならEMレーンの担当なのでスキップする。
# 差し戻すとEMタスクが起票そばからTodoへ戻り続ける
echo '{"data": {"issues": {"nodes": [{"id": "i9", "identifier": "NSY-30", "title": "EMタスク", "description": "repo行がない本文", "url": "u", "labels": {"nodes": [{"name": "role:manager"}]}}]}}}' >"$tmp/ready-em.json"
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
out42=$(HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-em.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" 2>&1)
check "role:managerはclaudeを実行しない" test ! -s "$CLAUDE_LOG"
check "role:managerはTodoへ差し戻さない" bash -c "! grep -q '\"$STATE_TODO\"' '$CURL_LOG'"
check "role:managerはEMレーン担当としてスキップと出る" grep -q "NSY-30: SKIPPED (EMレーン)" <<<"$out42"

# 5. claude失敗 → エラーコメント＋Todoへ差し戻し
cat >"$tmp/bin/claude" <<'EOF'
#!/bin/bash
echo "$*" >> "${CLAUDE_LOG:?}"
echo "something went wrong" >&2
exit 1
EOF
chmod +x "$tmp/bin/claude"
: >"$CURL_LOG"
: >"$CLAUDE_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-one.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" >/dev/null 2>&1
check "失敗時はTodo(s2)へ差し戻す" grep -q "\"$STATE_TODO\"" "$CURL_LOG"
check "失敗ログがコメントされる" grep -q "went wrong" "$CURL_LOG"

[[ "${KEEP_TMP:-0}" == "1" ]] && echo "tmp: $tmp" || rm -rf "$tmp"
echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
