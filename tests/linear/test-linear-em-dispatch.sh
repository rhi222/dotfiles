#!/bin/bash
# EMレーンはrole:managerかつrepo:行もPR URLも無いissueだけを対象にする。
# codex/curlをstubにし、実vaultや共有systemは変更しない。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
SCRIPT="$SCRIPTS_DIR/linear/em-dispatch.sh"
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
mkdir -p "$tmp/home/.config/linear" "$tmp/bin" "$tmp/vault/01_Inbox/ai"
echo "lin_api_test" >"$tmp/home/.config/linear/api-key"
export STATE_TRIAGE="s1" STATE_TODO="s2" STATE_AI_QUEUED="s3" STATE_AI_RUNNING="s4"
export STATE_MY_REVIEW="s5" STATE_DONE="s6" STATE_IN_PROGRESS="s7" STATE_WAITING="s8"
cat >"$tmp/home/.config/linear/config.json" <<EOF
{"team_id": "t1",
 "states": {"Triage": "$STATE_TRIAGE", "Todo": "$STATE_TODO", "AI Queued": "$STATE_AI_QUEUED", "AI Running": "$STATE_AI_RUNNING", "My Review": "$STATE_MY_REVIEW", "Done": "$STATE_DONE", "In Progress": "$STATE_IN_PROGRESS", "Waiting": "$STATE_WAITING"},
 "labels": {"src:jira": "l3", "src:slack": "l4", "src:github": "l5", "src:mtg": "l6"}}
EOF

# --- 関数単体テスト（sourceして呼ぶ） ---
export LINEAR_CONFIG_DIR="$tmp/home/.config/linear"
# VAULT は source 時に NIPPO_VAULT から決まるので、source より前に設定する
export NIPPO_VAULT="$tmp/vault"
export LINEAR_EM_STATE_DIR="$tmp/state"
# shellcheck source=/dev/null
source "$SCRIPT"
set +eo pipefail

issue_em=$(jq -n '{id:"i1", identifier:"NSY-12", title:"分類案をつくる",
  description:"予約のコア/カスタマイズ/拡張を分類したい",
  labels:{nodes:[{name:"role:manager"},{name:"em:product"}]}}')
issue_repo=$(jq -n '{id:"i2", identifier:"NSY-20", title:"実装",
  description:"repo: github.com/example-org/repo1",
  labels:{nodes:[{name:"role:manager"}]}}')
issue_pr=$(jq -n '{id:"i3", identifier:"NSY-21", title:"draft仕上げ",
  description:"元URL: https://github.com/example-org/repo1/pull/42",
  labels:{nodes:[{name:"role:manager"}]}}')
issue_player=$(jq -n '{id:"i4", identifier:"NSY-22", title:"repo無しplayer",
  description:"本文だけ", labels:{nodes:[{name:"role:player"}]}}')
issue_blocked=$(jq -n '{id:"i5", identifier:"NSY-112", title:"ヒアリング",
  description:"本文だけ",
  labels:{nodes:[{name:"role:manager"},{name:"ai:blocked-human"}]}}')

check "role:managerでrepo行もPRも無ければEMレーン" em_is_em_lane "$issue_em"
check "repo行があればEMレーンではない" bash -c "source '$SCRIPT'; ! em_is_em_lane '$issue_repo'"
check "PR URLがあればEMレーンではない" bash -c "source '$SCRIPT'; ! em_is_em_lane '$issue_pr'"
check "role:playerはEMレーンではない" bash -c "source '$SCRIPT'; ! em_is_em_lane '$issue_player'"
check "ai:blocked-humanはEMレーンではない" bash -c "source '$SCRIPT'; ! em_is_em_lane '$issue_blocked'"

# --- プロンプト生成 ---
prompt=$(em_build_prompt "$issue_em")
check "プロンプトにidentifierが入る" grep -q "NSY-12" <<<"$prompt"
check "プロンプトにタイトルが入る" grep -q "分類案をつくる" <<<"$prompt"
check "プロンプトに本文が入る" grep -q "予約のコア" <<<"$prompt"
check "プロンプトに成果物の置き場が入る" grep -q "01_Inbox/ai/" <<<"$prompt"
check "プロンプトにnippo-goalsの参照が入る" grep -q "nippo-goals.md" <<<"$prompt"
check "プロンプトに外部書き込み禁止が入る" grep -q "Slack" <<<"$prompt"

# --- 出力検証 ---
good="$tmp/good.json"
jq -n '{draft_path:"01_Inbox/ai/NSY-12-x.md", summary:"s",
  questions:[{q:"q1",why:"w1",options:["a","b"]},
             {q:"q2",why:"w2",options:["a","b"]},
             {q:"q3",why:"w3",options:["a","b"]}],
  next_action:"n"}' >"$good"
: >"$tmp/vault/01_Inbox/ai/NSY-12-x.md"
check "妥当な出力は検証を通る" em_validate_output "$good"

missing="$tmp/missing.json"
jq -n '{summary:"s", questions:[], next_action:"n"}' >"$missing"
check "draft_pathが無ければ非0" bash -c "source '$SCRIPT'; ! em_validate_output '$missing'"

fewq="$tmp/fewq.json"
jq -n '{draft_path:"01_Inbox/ai/NSY-12-x.md", summary:"s",
  questions:[{q:"q1",why:"w1",options:["a","b"]}], next_action:"n"}' >"$fewq"
check "質問が3件未満なら非0" bash -c "source '$SCRIPT'; ! em_validate_output '$fewq'"

nofile="$tmp/nofile.json"
jq -n '{draft_path:"01_Inbox/ai/NOPE.md", summary:"s",
  questions:[{q:"q1",why:"w1",options:["a","b"]},
             {q:"q2",why:"w2",options:["a","b"]},
             {q:"q3",why:"w3",options:["a","b"]}],
  next_action:"n"}' >"$nofile"
check "draft_pathのファイルが無ければ非0" bash -c "source '$SCRIPT'; ! em_validate_output '$nofile'"

broken="$tmp/broken.json"
echo 'not json' >"$broken"
check "JSONとして壊れていれば非0" bash -c "source '$SCRIPT'; ! em_validate_output '$broken'"

# --- スクリプト全体のテスト ---
cat >"$tmp/bin/curl" <<'EOF'
#!/bin/bash
data=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--data" ]]; then data="$2"; echo "$2" >> "${CURL_LOG:?}"; shift 2; else shift; fi
done
if grep -q 'viewer' <<<"$data"; then
  echo '{"data": {"viewer": {"id": "user-me"}}}'
elif grep -q "\"${STATE_MY_REVIEW:?}\"" <<<"$data"; then
  cat "${WIP_RESPONSE:?}"
elif grep -q 'issues(' <<<"$data"; then
  cat "${READY_RESPONSE:?}"
elif grep -q 'issueUpdate' <<<"$data"; then
  if [[ -n "${MOVE_FAIL:-}" ]]; then
    echo '{"errors": [{"message": "rate limited"}]}'
    exit 0
  fi
  echo '{"data": {"issueUpdate": {"success": true}}}'
else
  echo '{"data": {"commentCreate": {"success": true}}}'
fi
EOF
chmod +x "$tmp/bin/curl"

# stub codex: -o で指定されたファイルへ正常な出力を書き、叩き台も作る
cat >"$tmp/bin/codex" <<'EOF'
#!/bin/bash
echo "$*" >> "${CODEX_LOG:?}"
out=""
prev=""
for a in "$@"; do
  [[ "$prev" == "-o" ]] && out="$a"
  prev="$a"
done
[[ "${CODEX_FAIL:-0}" == "1" ]] && { echo "codex failed hard" >&2; exit 1; }
mkdir -p "${VAULT_DIR:?}/01_Inbox/ai"
echo "# 叩き台" > "${VAULT_DIR:?}/01_Inbox/ai/NSY-12-x.md"
cat > "$out" <<'JSON'
{"draft_path":"01_Inbox/ai/NSY-12-x.md","summary":"要約",
 "questions":[{"q":"境界をどこで切りますか","why":"合意が原則までだから","options":["課金の有無","責任主体"]},
              {"q":"誰に最初に見せますか","why":"順序は本人判断だから","options":["予約チーム","技術MG"]},
              {"q":"拡張を残しますか","why":"KPIの測り方が変わるから","options":["残す","残さない"]}],
 "next_action":"回答を受けて仕上げる"}
JSON
EOF
chmod +x "$tmp/bin/codex"

export PATH="$tmp/bin:$PATH"
export CURL_LOG="$tmp/curl.log"
export CODEX_LOG="$tmp/codex.log"
export CODEX_BIN="codex"
export VAULT_DIR="$tmp/vault"
export NIPPO_VAULT="$tmp/vault"
export LINEAR_EM_STATE_DIR="$tmp/state"
: >"$CURL_LOG"
: >"$CODEX_LOG"

echo '{"data": {"issues": {"nodes": []}}}' >"$tmp/wip-empty.json"
jq -n '{data: {issues: {nodes: [range(10) | {id: "i\(.)", identifier: "NSY-\(.)", title: "t", description: "", labels: {nodes: []}}]}}}' >"$tmp/wip-full.json"
jq -n '{data: {issues: {nodes: [
  {id:"i1", identifier:"NSY-12", title:"分類案をつくる", description:"予約のコア/カスタマイズ/拡張",
   labels:{nodes:[{name:"role:manager"},{name:"em:product"}]}}
]}}}' >"$tmp/ready-em.json"
jq -n '{data: {issues: {nodes: [
  {id:"i2", identifier:"NSY-20", title:"実装", description:"repo: github.com/example-org/repo1",
   labels:{nodes:[{name:"role:manager"}]}}
]}}}' >"$tmp/ready-repo.json"

# 1. フラグなし → 静かにスキップ
out1=$(HOME="$tmp/home" bash "$SCRIPT" run 2>&1)
check "フラグなしで静かにスキップ" test -z "$out1"

touch "$tmp/home/.config/linear-em-dispatch-enabled"

# 2. WIP上限超過 → 実行しない
: >"$CODEX_LOG"
out2=$(HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-full.json" READY_RESPONSE="$tmp/ready-em.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" run 2>&1)
check "WIP上限超過でスキップする" grep -q "WIP" <<<"$out2"
check "WIP超過時はcodexを実行しない" test ! -s "$CODEX_LOG"

# 3. 正常系
: >"$CURL_LOG"
: >"$CODEX_LOG"
# out1 / out2 と違い、この回は出力そのものを見ない。検査対象は CURL_LOG と
# CODEX_LOG に残る副作用なので、変数へ溜めず捨てる。
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-em.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" run >/dev/null 2>&1
check "codexが実行される" test -s "$CODEX_LOG"
check "codexにoutput-schemaを渡す" grep -q -- "--output-schema" "$CODEX_LOG"
# stdinを閉じ忘れるとcodexがEOF待ちで固まる（実測で5分返らず）。
# 実行時に検出しようとしてもテスト環境のstdinは常に非ttyなので無条件に通ってしまう。
# 関数定義そのものを見て、リダイレクトが書かれていることを保証する
check "em_run_codexがcodexのstdinを閉じている" bash -c "source '$SCRIPT'; declare -f em_run_codex | grep -q '/dev/null'"
# issue本文（外部テキスト）をプロンプトに埋めるので、サンドボックスで
# ネットワークを塞いでプロンプトインジェクションの外部送信経路を止める。
# 実行時のネットワーク遮断検証は現実的でないので、関数定義を静的に見る
check "em_run_codexがcodexのネットワークを塞いでいる" bash -c "source '$SCRIPT'; declare -f em_run_codex | grep -q 'network_access=false'"
check "AI Running(s4)へ遷移する" bash -c "grep issueUpdate '$CURL_LOG' | grep -q '\"$STATE_AI_RUNNING\"'"
check "My Review(s5)へ遷移する" bash -c "grep issueUpdate '$CURL_LOG' | grep -q '\"$STATE_MY_REVIEW\"'"
check "質問がコメントされる" grep -q "境界をどこで切りますか" "$CURL_LOG"
check "成果物パスがコメントされる" grep -q "01_Inbox/ai/NSY-12-x.md" "$CURL_LOG"
check "出力JSONが状態ディレクトリに残る" test -f "$tmp/state/NSY-12.json"

# 4. 実装レーンのissueは拾わない
: >"$CURL_LOG"
: >"$CODEX_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-repo.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" run >/dev/null 2>&1
check "repo行のissueはcodexを実行しない" test ! -s "$CODEX_LOG"
check "repo行のissueはstateを動かさない" bash -c "! grep -q issueUpdate '$CURL_LOG'"

# 5. AI Running遷移に失敗したら着手しない（二重実行の防止）
: >"$CURL_LOG"
: >"$CODEX_LOG"
out5=$(HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-em.json" \
  MOVE_FAIL=1 LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" run 2>&1)
check "AI Running遷移失敗ならcodexを実行しない" test ! -s "$CODEX_LOG"
check "AI Running遷移失敗はSKIPPEDと出る" grep -q "SKIPPED" <<<"$out5"

# 6. codex失敗 → Todoへ差し戻し＋ログをコメント
: >"$CURL_LOG"
: >"$CODEX_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-em.json" \
  CODEX_FAIL=1 LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" run >/dev/null 2>&1
check "codex失敗ならTodo(s2)へ差し戻す" grep -q "\"$STATE_TODO\"" "$CURL_LOG"
check "codex失敗ならログがコメントされる" grep -q "codex failed hard" "$CURL_LOG"

# 7. 出力が不正 → Todoへ差し戻し
cat >"$tmp/bin/codex" <<'EOF'
#!/bin/bash
echo "$*" >> "${CODEX_LOG:?}"
out=""; prev=""
for a in "$@"; do [[ "$prev" == "-o" ]] && out="$a"; prev="$a"; done
echo '{"summary":"欠けている"}' > "$out"
EOF
chmod +x "$tmp/bin/codex"
: >"$CURL_LOG"
: >"$CODEX_LOG"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-em.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" run >/dev/null 2>&1
check "出力が不正ならTodo(s2)へ差し戻す" grep -q "\"$STATE_TODO\"" "$CURL_LOG"
check "出力が不正ならMy Reviewへ遷移しない" bash -c "! grep issueUpdate '$CURL_LOG' | grep -q '\"$STATE_MY_REVIEW\"'"

# 7-2. ロックが取れなければ何もしない（同時起動で二重実行しない）。
# enqueue が呼ばれるたびにワーカーを起動するので、必ず踏む経路
: >"$CURL_LOG"
: >"$CODEX_LOG"
mkdir -p "$tmp/state"
out72=$(flock "$tmp/state/em.lock" -c "HOME='$tmp/home' WIP_RESPONSE='$tmp/wip-empty.json' READY_RESPONSE='$tmp/ready-em.json' LINEAR_CONFIG_DIR='$tmp/home/.config/linear' bash '$SCRIPT' run" 2>&1)
check "ロックが取れなければ何もしないと出る" grep -q "既にワーカーが動いている" <<<"$out72"
check "ロックが取れなければcodexを実行しない" test ! -s "$CODEX_LOG"

# 8. enqueue: AI Queuedへ移してワーカーを切り離し起動する
cat >"$tmp/bin/setsid" <<'EOF'
#!/bin/bash
echo "$*" >> "${SETSID_LOG:?}"
EOF
chmod +x "$tmp/bin/setsid"
export SETSID_LOG="$tmp/setsid.log"
: >"$CURL_LOG"
: >"$SETSID_LOG"
jq -n '{data: {issues: {nodes: [
  {id:"i1", identifier:"NSY-12", title:"分類案をつくる", description:"予約のコア",
   labels:{nodes:[{name:"role:manager"}]}}
]}}}' >"$tmp/ready-todo.json"
HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-todo.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" enqueue NSY-12 >/dev/null 2>&1
check "enqueueでAI Queued(s3)へ遷移する" bash -c "grep issueUpdate '$CURL_LOG' | grep -q '\"$STATE_AI_QUEUED\"'"
check "enqueueでワーカーを切り離し起動する" grep -q "em-dispatch" "$SETSID_LOG"
check "enqueueはcodexを直接実行しない" bash -c "! grep -q 'output-schema' '$CODEX_LOG'"

# 9. 存在しないidentifierは黙って無視せず警告する
: >"$CURL_LOG"
out9=$(HOME="$tmp/home" WIP_RESPONSE="$tmp/wip-empty.json" READY_RESPONSE="$tmp/ready-todo.json" \
  LINEAR_CONFIG_DIR="$tmp/home/.config/linear" bash "$SCRIPT" enqueue NSY-999 2>&1)
check "見つからないidentifierは警告する" grep -q "NSY-999" <<<"$out9"

[[ "${KEEP_TMP:-0}" == "1" ]] && echo "tmp: $tmp" || rm -rf "$tmp"
echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
