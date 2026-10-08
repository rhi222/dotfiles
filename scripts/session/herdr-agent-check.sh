#!/bin/bash
# Claude / Codex が動いているのに session identity を Herdr が持っていない pane を数える。
#
# Herdr の native restore は、hook が報告した session ID だけを復元する。
# hook の報告は agent の邪魔をしないよう失敗を握りつぶすので、壊れても気づけない。
# 実際に、herdr 更新で HERDR_BIN_PATH が消えた path を指し、9日間報告が止まっていた。
#
# 末尾に `herdr-agent-check: UNREPORTED=<件数>` を出す。server が動いていなければ出さない。
set -uo pipefail

HERDR_BIN="${HERDR_BIN:-herdr}"

if ! list=$("$HERDR_BIN" pane list 2>/dev/null); then
  echo "herdr server が動いていないためスキップ"
  exit 0
fi

unreported=$(jq -r '
  .result.panes[]
  | select((.agent // "") != "" and .agent_session == null)
  | "\(.pane_id)\t\(.agent)\t\(.cwd // "")"' <<<"$list") || exit 1

if [[ -n "$unreported" ]]; then
  echo "session ID が未報告の agent pane（次の restart で復元されない）:"
  printf '%s\n' "$unreported" | sed 's/^/  /'
fi
echo "herdr-agent-check: UNREPORTED=$(grep -c . <<<"$unreported")"
