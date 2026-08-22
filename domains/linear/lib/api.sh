#!/bin/bash
# LinearドメインのGraphQL APIラッパー。cron/対話スクリプト共用。
#
# 認証: ~/.config/linear/api-key（chmod 600・1行）
# 設定: ~/.config/linear/config.json（scripts/linear-bootstrap.sh が生成）
# テストは LINEAR_CONFIG_DIR で設定位置を差し替え、curlをstubにする

LINEAR_API_URL="${LINEAR_API_URL:-https://api.linear.app/graphql}"
LINEAR_CONFIG_DIR="${LINEAR_CONFIG_DIR:-$HOME/.config/linear}"

linear_api_key() {
  local f="$LINEAR_CONFIG_DIR/api-key"
  [[ -r "$f" ]] || {
    echo "linear-api: api-keyが見つからない: $f" >&2
    return 1
  }
  tr -d '[:space:]' <"$f"
}

# linear_gql <query> [variables-json]
# レスポンスの .data をstdoutへ。errors[]が非空なら非0で失敗する
linear_gql() {
  local query="$1" vars="${2:-"{}"}"
  local key payload resp
  key=$(linear_api_key) || return 1
  # -c で1行にする。HTTP bodyとして自然で、ログの grep も行単位で効く
  payload=$(jq -nc --arg q "$query" --argjson v "$vars" '{query: $q, variables: $v}') || return 1
  resp=$(curl -sS -X POST "$LINEAR_API_URL" \
    -H "Authorization: $key" -H "Content-Type: application/json" \
    --data "$payload") || {
    echo "linear-api: HTTPエラー" >&2
    return 1
  }
  if jq -e '(.errors // []) | length > 0' <<<"$resp" >/dev/null 2>&1; then
    echo "linear-api: GraphQLエラー: $(jq -c '.errors' <<<"$resp")" >&2
    return 1
  fi
  jq '.data' <<<"$resp"
}

# linear_config <jq-path>  例) linear_config '.team_id'
linear_config() {
  local f="$LINEAR_CONFIG_DIR/config.json"
  [[ -r "$f" ]] || {
    echo "linear-api: configが見つからない: $f（scripts/linear-bootstrap.sh を実行）" >&2
    return 1
  }
  jq -er "$1" "$f"
}

linear_state_id() { linear_config ".states[\"$1\"]"; }
linear_label_id() { linear_config ".labels[\"$1\"]"; }

# linear_issues_in_state <state名>
#   → [{id, identifier, title, description, url, dueDate, createdAt, labels, parent, children}]
#
# dueDate / createdAt は「期日超過」「滞留日数」で優先順位を付けるために返す。
# labels は role/em の偏りを見るため、parent/children は親子の取り残し検出のため。
linear_issues_in_state() {
  local sid team
  sid=$(linear_state_id "$1") || return 1
  team=$(linear_config '.team_id') || return 1
  linear_gql 'query($team: ID!, $state: ID!) {
    issues(filter: {team: {id: {eq: $team}}, state: {id: {eq: $state}}}, first: 50) {
      nodes {
        id identifier title description url dueDate createdAt
        labels { nodes { name } }
        parent { identifier }
        children { nodes { identifier } }
      }
    }
  }' "$(jq -n --arg t "$team" --arg s "$sid" '{team: $t, state: $s}')" | jq '.issues.nodes'
}

# linear_viewer_id → 認証ユーザーのid（同一プロセス内でキャッシュする）
linear_viewer_id() {
  if [[ -z "${_linear_viewer_id:-}" ]]; then
    _linear_viewer_id=$(linear_gql '{ viewer { id } }' | jq -er '.viewer.id') || return 1
  fi
  echo "$_linear_viewer_id"
}

# linear_activity_since <YYYY-MM-DD>
#   → 指定日以降に更新されたissue [{identifier, title, url, updatedAt, state, labels, project, parent}]
#
# 日報の作業サマリ（今日動いたもの）と週次の傾向分析（role/em の配分）で使う。
# updatedAt は state遷移・コメント・本文編集で更新されるので「触った」の代理指標になる。
#
# canceled / duplicate は除外する。閉じたissueにラベルを付け直すことはないので、
# 集計に混ざると「ラベル未設定」が水増しされて配分が読めなくなる。
# Done は成果なので残す。
linear_activity_since() {
  local team
  team=$(linear_config '.team_id') || return 1
  linear_gql 'query($team: ID!, $since: DateTimeOrDuration!) {
    issues(filter: {team: {id: {eq: $team}}, updatedAt: {gte: $since},
                    state: {type: {nin: ["canceled", "duplicate"]}}},
           orderBy: updatedAt, first: 100) {
      nodes {
        identifier title url updatedAt
        state { name type }
        labels { nodes { name } }
        project { name }
        parent { identifier }
      }
    }
  }' "$(jq -n --arg t "$team" --arg s "$1" '{team: $t, since: $s}')" | jq '.issues.nodes'
}

# linear_cycle_issues
#   → 進行中のCycleのissue [{identifier, title, url, estimate, dueDate, state, labels, parent, children}]
#
# 「今日やる3件」の候補（`nippo-add`）と、Cycle内の親子二重計上チェック（`linear-triage`）で使う。
#
# 候補をTodo全体（42件）ではなくCycle（16件）から取るのは、件数の問題だけではない。
# Cycleは「今週やると自分で宣言したもの」なので、期日や滞留日数といった機械的な代理指標より
# 選定の根拠が強い。
#
# state での絞り込みはしない。呼び出し側の用途が違うため（候補選びはopenだけ見たいが、
# 二重計上チェックはCycleの中身を全部見る必要がある）。フィルタはjq側でやる。
#
# アクティブなCycleが無い週は空配列を返す。日報作成もtriageも止めない。
linear_cycle_issues() {
  local team
  team=$(linear_config '.team_id') || return 1
  linear_gql 'query($team: ID!) {
    cycles(filter: {team: {id: {eq: $team}}, isActive: {eq: true}}, first: 1) {
      nodes {
        number startsAt endsAt
        issues(first: 100) {
          nodes {
            identifier title url estimate dueDate
            state { name type }
            labels { nodes { name } }
            parent { identifier }
            children { nodes { identifier } }
          }
        }
      }
    }
  }' "$(jq -n --arg t "$team" '{team: $t}')" | jq '.cycles.nodes[0].issues.nodes // []'
}

# linear_issue_create <title> <description> <state名> [label名...] → {id, identifier, url}
#
# assigneeは常に自分。個人の司令塔なので未アサインだと My Issues に出てこない
# labelは可変長。role:* / em:* を起票時に付けられるようにしてある
# （src:* だけだと後からまとめてバックフィルする羽目になる）
linear_issue_create() {
  local title="$1" desc="$2" state="$3"
  shift 3
  local team sid me input lid label
  team=$(linear_config '.team_id') || return 1
  sid=$(linear_state_id "$state") || return 1
  me=$(linear_viewer_id) || return 1
  input=$(jq -n --arg t "$team" --arg ti "$title" --arg d "$desc" --arg s "$sid" --arg a "$me" \
    '{teamId: $t, title: $ti, description: $d, stateId: $s, assigneeId: $a, labelIds: []}')
  for label in "$@"; do
    [[ -n "$label" ]] || continue
    lid=$(linear_label_id "$label") || return 1
    input=$(jq --arg l "$lid" '.labelIds += [$l]' <<<"$input")
  done
  linear_gql 'mutation($input: IssueCreateInput!) {
    issueCreate(input: $input) { success issue { id identifier url } }
  }' "$(jq -n --argjson i "$input" '{input: $i}')" | jq '.issueCreate.issue'
}

# linear_issue_move <issueId> <state名>
linear_issue_move() {
  local sid
  sid=$(linear_state_id "$2") || return 1
  linear_gql 'mutation($id: String!, $state: String!) {
    issueUpdate(id: $id, input: {stateId: $state}) { success }
  }' "$(jq -n --arg i "$1" --arg s "$sid" '{id: $i, state: $s}')" >/dev/null
}

# linear_comment <issueId> <body>
linear_comment() {
  linear_gql 'mutation($id: String!, $body: String!) {
    commentCreate(input: {issueId: $id, body: $body}) { success }
  }' "$(jq -n --arg i "$1" --arg b "$2" '{id: $i, body: $b}')" >/dev/null
}
