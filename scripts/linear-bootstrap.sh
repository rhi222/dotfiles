#!/bin/bash
# Linearのteam/state/label IDを解決して ~/.config/linear/config.json を生成する
#
# 前提: Linear UI（またはAPI）でstate/labelを作成済み。不足があれば名前を表示して失敗する。
# ラベルは「issue labels」であること。project labelsは別物で、ここでは拾わない。
#
# 使い方: bash scripts/linear-bootstrap.sh
# teamが複数ある場合: LINEAR_TEAM_KEY=NSY bash scripts/linear-bootstrap.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/linear-api.sh"

REQUIRED_STATES=("Triage" "Todo" "In Progress" "AI Queued" "AI Running" "My Review" "Waiting" "Done")
REQUIRED_LABELS=("src:jira" "src:slack" "src:github" "src:mtg" "role:player" "role:manager" "em:people" "em:tech" "em:project" "em:product")

data=$(linear_gql '{ teams { nodes { id key name
  states { nodes { id name } }
  labels { nodes { id name } } } } }')

team_count=$(jq '.teams.nodes | length' <<<"$data")
if [[ "$team_count" -ne 1 ]]; then
  if [[ -z "${LINEAR_TEAM_KEY:-}" ]]; then
    echo "linear-bootstrap: teamが${team_count}件ある。LINEAR_TEAM_KEY=<key> で指定してほしい" >&2
    exit 1
  fi
  data=$(jq --arg k "$LINEAR_TEAM_KEY" '{teams: {nodes: [.teams.nodes[] | select(.key == $k)]}}' <<<"$data")
  if [[ "$(jq '.teams.nodes | length' <<<"$data")" -ne 1 ]]; then
    echo "linear-bootstrap: LINEAR_TEAM_KEY=$LINEAR_TEAM_KEY に一致するteamが無い" >&2
    exit 1
  fi
fi
team=$(jq '.teams.nodes[0]' <<<"$data")

missing=()
for s in "${REQUIRED_STATES[@]}"; do
  jq -e --arg n "$s" '.states.nodes[] | select(.name == $n)' <<<"$team" >/dev/null || missing+=("state: $s")
done
for l in "${REQUIRED_LABELS[@]}"; do
  jq -e --arg n "$l" '.labels.nodes[] | select(.name == $n)' <<<"$team" >/dev/null || missing+=("label: $l")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "linear-bootstrap: 以下を作成してから再実行してほしい" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

out="$LINEAR_CONFIG_DIR/config.json"
jq '{
  team_id: .id,
  team_key: .key,
  states: (.states.nodes | map({(.name): .id}) | add),
  labels: (.labels.nodes | map({(.name): .id}) | add)
}' <<<"$team" >"$out"
echo "linear-bootstrap: $out を生成した"
