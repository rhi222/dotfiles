#!/bin/bash
# Linearの未完了issueから、followupで追うSlackスレを取り出す。
# stdout: skill向けの読み取り指示（dotctl followup targets の出力）
# 副作用: 状態ディレクトリの targets.json を書き換える（dotctl側）
#
# Linearが失敗したら dotctl を呼ばない。空の対象で targets.json を上書きすると、
# 次のapplyで全スレの状態が消え、復帰後に🆕が出なくなる。
set -euo pipefail

DOMAIN_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
REPO_ROOT="$(cd "$DOMAIN_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib/linear-api.sh"

team=$(linear_config '.team_id')
# ponytail: 250件まで。未完了がこれを超えたらpaginationを足す
issues=$(linear_gql 'query($team: ID!) {
  issues(filter: {team: {id: {eq: $team}},
                  state: {type: {nin: ["completed", "canceled", "duplicate"]}}}, first: 250) {
    nodes { identifier title url description }
  }
}' "$(jq -n --arg t "$team" '{team: $t}')" | jq -e '.issues.nodes | arrays')
dotctl followup targets --in - <<<"$issues"
