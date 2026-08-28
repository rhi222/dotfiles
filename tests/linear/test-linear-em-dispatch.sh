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

[[ "${KEEP_TMP:-0}" == "1" ]] && echo "tmp: $tmp" || rm -rf "$tmp"
echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
