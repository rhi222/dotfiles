#!/bin/bash
# 夜間PR見張りは、自分のopen PRのうちCI失敗か未対応レビューがあるものだけを直す。
# pushはdraft PRだけで、レビュー中のPRは修正をworktreeに残して朝の判断に回す。
# gh/claude/ghqをstubにし、gitはmktemp内の実repositoryで検証する。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/prwatch/nightly.sh"
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
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME/.config" "$tmp/bin"
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --global user.name tester
git config --global user.email tester@example.com
git config --global init.defaultBranch main

# --- 実repository（remote + ghq配下のclone）---
REPO="$tmp/ghq/github.com/example-org/repo1"
git init -q --bare "$tmp/remote.git"
git clone -q "$tmp/remote.git" "$REPO" 2>/dev/null
git -C "$REPO" commit -q --allow-empty -m init
git -C "$REPO" push -q origin main
for b in feat1 feat2 feat3; do
  git -C "$REPO" checkout -q -b "$b" main
  git -C "$REPO" commit -q --allow-empty -m "$b"
  git -C "$REPO" push -q origin "$b"
done
git -C "$REPO" checkout -q main
remote_sha() { git -C "$tmp/remote.git" rev-parse "$1"; }
export SHA1 SHA2 SHA3
SHA1=$(remote_sha feat1)
SHA2=$(remote_sha feat2)
SHA3=$(remote_sha feat3)

# --- stub ---
# PR1: draft・CI失敗 / PR2: ready・未解決スレッド / PR3: 全部緑（resolvedとoutdatedだけ）
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >> "${GH_LOG:?}"
case "$1 $2" in
  "search prs")
    echo '[{"url":"https://github.com/example-org/repo1/pull/1"},
           {"url":"https://github.com/example-org/repo1/pull/2"},
           {"url":"https://github.com/example-org/repo1/pull/3"}]' ;;
  "api graphql")
    n=$(grep -oE 'number=[0-9]+' <<<"$*" | cut -d= -f2)
    case "$n" in
      1) jq -n --arg s "$SHA1" '{data:{repository:{pullRequest:{headRefName:"feat1",headRefOid:$s,isDraft:true,
            reviewDecision:null, commits:{nodes:[{commit:{statusCheckRollup:{state:"FAILURE"}}}]},
            reviewThreads:{nodes:[]}}}}}' ;;
      2) jq -n --arg s "$SHA2" '{data:{repository:{pullRequest:{headRefName:"feat2",headRefOid:$s,isDraft:false,
            reviewDecision:"REVIEW_REQUIRED", commits:{nodes:[{commit:{statusCheckRollup:{state:"SUCCESS"}}}]},
            reviewThreads:{nodes:[{isResolved:false,isOutdated:false,path:"a.go",line:3,
              comments:{nodes:[{body:"REVIEW-SAYS-RENAME",author:{login:"alice"}}]}}]}}}}}' ;;
      3) jq -n --arg s "$SHA3" '{data:{repository:{pullRequest:{headRefName:"feat3",headRefOid:$s,isDraft:false,
            reviewDecision:"APPROVED", commits:{nodes:[{commit:{statusCheckRollup:{state:"SUCCESS"}}}]},
            reviewThreads:{nodes:[{isResolved:true,isOutdated:false,path:"b.go",line:1,comments:{nodes:[]}},
                                  {isResolved:false,isOutdated:true,path:"c.go",line:1,comments:{nodes:[]}}]}}}}}' ;;
    esac ;;
  "run list") echo '[{"databaseId":77}]' ;;
  "run view") echo "CI-FAILED-LOG-LINE" ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
# claude: cwd（worktree）でコミットを1つ積む。CLAUDE_NO_COMMIT=1 なら積まない
cat >"$tmp/bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n---END---\n' "$*" >> "${CLAUDE_LOG:?}"
[[ "${CLAUDE_NO_COMMIT:-0}" == "1" ]] || git commit -q --allow-empty -m "fix by agent"
# 判断理由は先頭に来ることが多い。末尾だけ残すと朝に読めないので複数行を出す
printf 'AGENT-REASON-FIRST-LINE\nline2\nline3\nline4\ndone\n'
EOF
cat >"$tmp/bin/ghq" <<'EOF'
#!/bin/bash
[[ "$1" == "root" ]] && echo "${GHQ_ROOT:?}"
EOF
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" GHQ_ROOT="$tmp/ghq" CLAUDE_BIN="$tmp/bin/claude"
export GH_LOG="$tmp/gh.log" CLAUDE_LOG="$tmp/claude.log"
export PR_WATCH_STATE_DIR="$tmp/state"
reset_logs() {
  : >"$GH_LOG"
  : >"$CLAUDE_LOG"
}

# --- 0. botのレビュー指摘も人の指摘と同じく拾う（AIレビューbotの指摘にも対応したいため）---
bot_pr='{"reviewDecision":null,"commits":{"nodes":[]},"reviewThreads":{"nodes":[{"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"github-actions"}}]}}]}}'
check "botだけのレビュー指摘もfeedbackとして拾う" test "$(bash -c 'source "$1"; prwatch_reasons "$2"' _ "$(dirname "$SCRIPT")/../../internal/prwatch/scripts/nightly.sh" "$bot_pr")" = "feedback"

# --- 1. 無効なら何もしない ---
reset_logs
bash "$SCRIPT" >/dev/null 2>&1
check "有効化フラグが無ければghを呼ばない" test ! -s "$GH_LOG"

# --- 2. dry-run は判定だけ出し、agentを起動しない ---
reset_logs
out=$(bash "$SCRIPT" --dry-run 2>&1)
check "dry-runはフラグ無しでも判定する" grep -q 'pull/1' <<<"$out"
check "dry-runはagentを起動しない" test ! -s "$CLAUDE_LOG"
check "dry-runでCI失敗を理由に出す" grep -qE 'pull/1.*ci' <<<"$out"
check "dry-runで未対応レビューを理由に出す" grep -qE 'pull/2.*feedback' <<<"$out"
check "resolved・outdatedだけのPRは対象外" bash -c "! grep -q 'pull/3' <<<\"\$1\"" _ "$out"

# --- 3. 本実行 ---
touch "$HOME/.config/pr-watch-enabled"
reset_logs
out=$(bash "$SCRIPT" 2>&1)
check "draft PRの修正はpushされる" test "$(remote_sha feat1)" != "$SHA1"
check "draft PRのworktreeは片付く" test ! -d "$REPO/.wt/pr-watch-1"
check "レビュー中PRの修正はpushしない" test "$(remote_sha feat2)" = "$SHA2"
check "レビュー中PRの修正はworktreeに残る" test -d "$REPO/.wt/pr-watch-2"
check "レビュー中PRはpush待ちと報告する" grep -qE 'pull/2.*push待ち' <<<"$out"
check "緑のPRにはagentを起動しない" test "$(grep -c -- '---END---' "$CLAUDE_LOG")" = "2"
check "CIの失敗ログをプロンプトに渡す" grep -q 'CI-FAILED-LOG-LINE' "$CLAUDE_LOG"
check "レビュー指摘の本文をプロンプトに渡す" grep -q 'REVIEW-SAYS-RENAME' "$CLAUDE_LOG"
check "agentにghを渡さない" bash -c "! grep -q 'Bash(gh' \"\$1\"" _ "$CLAUDE_LOG"
check "ローカルのfeatブランチは動かさない" test "$(git -C "$REPO" rev-parse feat1)" = "$SHA1"
check "実行結果をlast-runに残す" grep -q 'pull/2' "$PR_WATCH_STATE_DIR/last-run.txt"
check "agentの出力全文をPRごとに残す" grep -q 'AGENT-REASON-FIRST-LINE' "$PR_WATCH_STATE_DIR/example-org_repo1_2.log"
check "結果行に出力全文の場所を示す" grep -qE 'pull/2.*example-org_repo1_2\.log' <<<"$out"
# プロンプトをPRごとに切り出す（claude stubは呼び出しごとに ---END--- で区切る）
prompt_of() { awk -v pr="pull/$1 " 'BEGIN{RS="---END---"} index($0, pr){print}' "$CLAUDE_LOG"; }
check "CI失敗のPRにはCIログ欄を入れる" grep -q 'CIの失敗ログ' <<<"$(prompt_of 1)"
check "指摘だけのPRにはCIログ欄を入れない" bash -c "! grep -q 'CIの失敗ログ' <<<\"\$1\"" _ "$(prompt_of 2)"
check "CIが落ちていないPRには未対応指摘欄だけを入れる" grep -q '未対応のレビュー指摘' <<<"$(prompt_of 2)"

# --- 4. 再実行: push済みのheadと、push待ちのworktreeは触らない ---
# PR1はpush後のheadを記録しているはず。stubのheadRefOidをそれに合わせて再実行する
export SHA1
SHA1=$(remote_sha feat1)
reset_logs
out=$(bash "$SCRIPT" 2>&1)
check "対応済みheadのPRには再度agentを起動しない" test ! -s "$CLAUDE_LOG"
check "push待ちのworktreeがあるPRはスキップと報告する" grep -qE 'pull/2.*push待ち' <<<"$out"

# --- 5. コミットが積まれなければpushせず、同じheadで繰り返さない ---
git -C "$REPO" worktree remove --force "$REPO/.wt/pr-watch-2"
rm -rf "$PR_WATCH_STATE_DIR"
export CLAUDE_NO_COMMIT=1
reset_logs
out=$(bash "$SCRIPT" 2>&1)
check "コミットが無ければpushしない" test "$(remote_sha feat1)" = "$SHA1"
check "コミットが無ければworktreeを残さない" test ! -d "$REPO/.wt/pr-watch-2"
reset_logs
bash "$SCRIPT" >/dev/null 2>&1
check "直せなかったheadでは翌晩も繰り返さない" test ! -s "$CLAUDE_LOG"

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
