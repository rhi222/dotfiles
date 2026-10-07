#!/bin/bash
# followup digest-cron.sh のテスト
#
# 重要: --allowedTools にSlack・Jiraの書き込み系が含まれていないことを検証する。
# 「書き込まない」の担保が許可リストそのものなので、ここが唯一の防壁になる。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
SCRIPT="$SCRIPTS_DIR/followup/digest-cron.sh"
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

# 1. フラグなし → 何もせず正常終了
mkdir -p "$TMP/h1"
out1=$(HOME="$TMP/h1" bash "$SCRIPT" 2>&1)
check "フラグなしで静かにスキップする" test -z "$out1"

# 2. DRY_RUN
H="$TMP/h2"
mkdir -p "$H/.config"
touch "$H/.config/followup-enabled"
out2=$(HOME="$H" FOLLOWUP_DRY_RUN=1 FOLLOWUP_FORCE=1 bash "$SCRIPT" 2>&1)
check "DRY_RUNで実行内容を表示する" grep -q "DRY_RUN" <<<"$out2"
check "followup skillを呼ぶ" grep -q "/followup" <<<"$out2"
check "timeoutを噛ませる" grep -q "timeout " <<<"$out2"
out2b=$(HOME="$H" FOLLOWUP_DRY_RUN=1 FOLLOWUP_FORCE=1 FOLLOWUP_TIMEOUT=42 bash "$SCRIPT" 2>&1)
check "timeoutを環境変数で上書きできる" grep -q "timeout 42" <<<"$out2b"

# 3. 読み取り系だけを許可する
for t in 'Bash(dotctl:\*)' slack_search_public_and_private slack_read_thread slack_read_user_profile \
  getAccessibleAtlassianResources searchJiraIssuesUsingJql; do
  check "許可する: $t" grep -q "$t" <<<"$out2"
done
for t in slack_send_message slack_schedule_message slack_create_canvas slack_update_canvas \
  createJiraIssue editJiraIssue addCommentToJiraIssue transitionJiraIssue addWorklogToJiraIssue \
  createIssueLink createConfluencePage updateConfluencePage 'Bash(bash:' 'Write'; do
  check "許可しない: $t" test "$(grep -c "$t" <<<"$out2")" -eq 0
done

# 4. claude成功 + noticeあり → toastを出してnoticeを消す
STATE="$TMP/state"
mkdir -p "$STATE" "$TMP/bin"
cat >"$TMP/bin/claude" <<STUB
#!/bin/bash
printf '返事1件・頼まれ事0件\n' >"$STATE/notice"
STUB
cat >"$TMP/bin/toast" <<STUB
#!/bin/bash
echo "TOAST \$*" >>"$TMP/toast.log"
STUB
chmod +x "$TMP/bin/claude" "$TMP/bin/toast"
HOME="$H" FOLLOWUP_FORCE=1 FOLLOWUP_STATE_DIR="$STATE" CLAUDE_BIN="$TMP/bin/claude" \
  FOLLOWUP_TOAST_CMD="$TMP/bin/toast" bash "$SCRIPT" >/dev/null 2>&1
check "noticeがあればtoastを出す" grep -q "返事1件" "$TMP/toast.log"
check "toast後にnoticeを消す" test ! -e "$STATE/notice"

# 5. claude失敗 → toastを出さない
rm -f "$TMP/toast.log"
printf '返事9件・頼まれ事9件\n' >"$STATE/notice"
printf '#!/bin/bash\nexit 1\n' >"$TMP/bin/claude"
HOME="$H" FOLLOWUP_FORCE=1 FOLLOWUP_STATE_DIR="$STATE" CLAUDE_BIN="$TMP/bin/claude" \
  FOLLOWUP_TOAST_CMD="$TMP/bin/toast" bash "$SCRIPT" >/dev/null 2>&1
check "claude失敗時はtoastを出さない" test ! -e "$TMP/toast.log"

# 6. symlink越しでもリポジトリを解決する
ln -s "$SCRIPTS_DIR" "$H/scripts"
out6=$(HOME="$H" FOLLOWUP_DRY_RUN=1 FOLLOWUP_FORCE=1 bash "$H/scripts/followup/digest-cron.sh" 2>&1)
check "symlink越しでもリポジトリを解決する" grep -q "$(dirname "$SCRIPTS_DIR")" <<<"$out6"

echo "---"
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
