# linear_gql 直叩きレシピ

`linear-api.sh` の高レベル関数で足りない操作はここのsnippetを使う。
GraphQLをその場で手書きしない（引数の渡し方やinputの形を毎回間違えるため）。

## ID解決ヘルパー

`linear-api.sh` に含まれる。snippet内で使う。

| 関数 | 返すもの |
| --- | --- |
| `linear_config '.team_id'` | チームID |
| `linear_state_id "<state名>"` | workflow stateのID |
| `linear_label_id "<label名>"` | ラベルID |
| `linear_viewer_id` | 認証ユーザー（自分）のID |

## issueCreate（Project・親子・複数ラベルを一度に設定）

**`assigneeId` は自動では付かないので必ず入れる。** `linear_issue_create` と違い、
付け忘れると My Issues に出ないissueが静かにできあがる。

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"
input=$(jq -n \
  --arg team "$(linear_config '.team_id')" \
  --arg state "$(linear_state_id 'Todo')" \
  --arg me "$(linear_viewer_id)" \
  --arg title "<title>" --arg desc "<description>" \
  '{teamId: $team, stateId: $state, assigneeId: $me, title: $title, description: $desc,
    labelIds: ["<labelId>"], projectId: "<projectId>", parentId: "<親issueのid>"}')
linear_gql 'mutation($input: IssueCreateInput!) {
  issueCreate(input: $input) { success issue { id identifier url } }
}' "$(jq -n --argjson i "$input" '{input: $i}')" | jq '.issueCreate.issue'
```

labelId は `linear_label_id` で引く。`projectId` / `parentId` は不要ならキーごと省く。

## 重複チェック（元URL / Jiraキーで既存issueを検索）

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"
linear_gql 'query($team: ID!, $q: String!) {
  issues(filter: {team: {id: {eq: $team}}, searchableContent: {contains: $q}}, first: 5) {
    nodes { identifier title url }
  }
}' "$(jq -n --arg t "$(linear_config '.team_id')" --arg q "<元URLまたはJiraキー>" '{team: $t, q: $q}')"
```

## 期日を設定する（dueDate）

型は `TimelessDate!`（`YYYY-MM-DD` 文字列）。Jiraの `duedate` をそのまま入れる。

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"
linear_gql 'mutation($id: String!, $d: TimelessDate!) {
  issueUpdate(id: $id, input: {dueDate: $d}) { success issue { identifier dueDate } }
}' "$(jq -n --arg i "<issueId>" --arg d "2026-08-05" '{id: $i, d: $d}')"
```

- **Jiraの `duedate` が null なら設定しない**（勝手に日付を作らない）。実測ではBETADEV系はほぼnull、ALPHADEV系（ST障害）は入っていることが多い
- 期日は**親課題にだけ**付ける。子（工程）はJiraに対応物が無い
- すでに過ぎている期日でもそのまま入れる（超過していること自体が判断材料になる）
- Linear UIに期日欄が見当たらないのは値が未設定なだけで、フィールド自体は常に存在する

## 番号からissue idを引く

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"
linear_gql 'query($n: Float!) { issues(filter: {number: {eq: $n}}) { nodes { id identifier title } } }' \
  "$(jq -n --argjson n 44 '{n: $n}')"
```

`number` の型は `Float!`。`--argjson` で数値として渡す（`--arg` の文字列だと型エラーになる）。
