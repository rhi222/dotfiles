---
name: linear-triage
description: Linearの夕方triageを支援する。Todoをスコアリングして「今夜AIに投げるもの」を提案し、承認されたissueを実行可能な形（repo行・指示・検証方法）に整形してAI Queuedへ遷移させる。あわせてTriageの受け入れと整合チェックを行う。「triage」「今夜の仕込み」「夜間dispatchの準備」「明日の準備」「Linearを整理」などで使用。
argument-hint: "（引数不要。件数を絞るなら数字）"
allowed-tools: Read, Bash(bash:*), Bash(source:*), Bash(jq:*), Bash(gh:*), Bash(ghq:*), Bash(grep:*), Bash(date:*), mcp__claude_ai_Atlassian__getJiraIssue
---

# Linear夕方triage

夜間dispatch（`scripts/linear/dispatch-cron.sh`）に渡すissueを選んで整形する。
設計の全体像は `~/Obsidian/01_Inbox/2026-08-06-linear-command-layer-design.md`。矛盾したら設計docが正。

GraphQLのsnippetは `../linear-add/references/api-recipes.md` を使う。

## 絶対に守ること

- **GitHub / Jira へ書き戻さない。** `gh` は読み取りのみ
- **勝手に `AI Queued` へ遷移させない。** 整形内容を必ず人間に見せて添削を受けてから反映する

## 手順

### 0. 状況を出す（まずこれだけ見せる）

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"
for s in "My Review" "AI Queued" "Triage" "Todo"; do
  printf '%s: %s件\n' "$s" "$(linear_issues_in_state "$s" | jq 'length')"
done
```

**「My Review」が10件（`LINEAR_WIP_LIMIT`）以上ならtriageを止める。**
生成速度＞判断速度で仕組みが破綻しているので、先に朝の判断を促す。
夜間dispatch側も同じ閾値で自動停止するため、仕込んでも実行されない。

### 1. 整合チェック（毎回やる）

実際に発生した崩れなので毎回見る。件数だけ出し、0件なら1行で済ませる。

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"

# 1) closedな親の下で開いている子（親を閉じたときの取り残し。実際に起きた）
linear_gql '{ issues(first: 100, filter: {state: {type: {nin: ["completed","canceled"]}}}) {
  nodes { identifier parent { identifier state { type } } } } }' \
| jq -r '.issues.nodes[] | select(.parent != null and (.parent.state.type | IN("completed","canceled")))
         | "\(.identifier) の親 \(.parent.identifier) が closed"'

# 2) Triageに残ったままの機械起票（スイープが落としたきり親に紐付いていない）
linear_issues_in_state "Triage" | jq -r '.[] | "\(.identifier)\t\(.title)"'

# 3) AI Queued なのに repo: 行が無く、EMレーンの対象でもない
#    （どちらのランナーも拾えないので、dispatchがTodoへ差し戻す前に気づける）
#    role:manager が付いていれば em-dispatch.sh の担当なので正常
linear_issues_in_state "AI Queued" \
| jq -r '.[] | select((.description // "") | test("(?m)^repo:") | not)
         | select([.labels.nodes[].name] | index("role:manager") | not) | .identifier'

# 4) My Reviewに非AI成果物が混ざっている（WIP上限が誤作動する。実際に起きた）
#    判定は「PR URLを持っているか」。My Reviewは四択（マージ/チームレビューへ/修正指示/破棄）を
#    掛ける場所なので、PRが無ければそもそも裁けない。継続モードは本文の 元URL:、
#    新規モードはdispatchの完了コメントにPR URLが入るので、両方を見る。
#    EMレーンの成果物はPRではなくvault内のMarkdownなので、01_Inbox/ai/ の
#    パスも正当な成果物として認める
linear_gql 'query($team: ID!, $state: ID!) {
  issues(filter: {team: {id: {eq: $team}}, state: {id: {eq: $state}}}, first: 50) {
    nodes { identifier title description comments(first: 20) { nodes { body } } } } }' \
  "$(jq -n --arg t "$(linear_config '.team_id')" --arg s "$(linear_state_id 'My Review')" '{team:$t,state:$s}')" \
| jq -r '.issues.nodes[]
         | select(([(.description // "")] + [.comments.nodes[].body] | join("\n")
                   | test("github\\.com/[^/\\s]+/[^/\\s]+/pull/|01_Inbox/ai/")) | not)
         | "\(.identifier) \(.title[0:40]) 成果物無し"'

# 5) role / em ラベルの欠落（週次の配分分析が読めなくなる）
linear_gql '{ issues(first: 100, filter: {state: {type: {nin: ["completed","canceled","duplicate"]}}}) {
  nodes { identifier title labels { nodes { name } } } } }' \
| jq -r '.issues.nodes[]
         | select(([.labels.nodes[].name|select(startswith("role:"))]|length)==0
               or ([.labels.nodes[].name|select(startswith("em:"))]|length)==0)
         | "\(.identifier) \(.title[0:40])"'

# 6) 期日超過
linear_issues_in_state "Todo" | jq -r --arg t "$(date +%F)" \
  '.[] | select(.dueDate != null and .dueDate < $t) | "\(.identifier) due=\(.dueDate)"'

# 7) Cycle内の親子二重計上（親と子が両方Cycleに載っている）
#    Cycleに載せるのは実作業単位。子があれば子だけを入れる（親も入れるとvelocityが二重計上になる）。
#    加えて「今日やる3件」の候補がCycle起点なので、放置すると親と子が並んで提案される
linear_cycle_issues | jq -r '
  map(.identifier) as $ids
  | .[] | select((.children.nodes|length) > 0)
  | . as $p | (.children.nodes | map(.identifier) | map(select(. as $c | $ids | index($c)))) as $dup
  | select(($dup|length) > 0)
  | "\($p.identifier)（親・est=\($p.estimate // "-")）と子 \($dup|join(",")) が同じCycleにいる"'

# 8) Cycle内のestimate未設定（velocityが読めない。1件も無いうちは無視してよい）
linear_cycle_issues | jq -r '
  .[] | select(.estimate == null and (.state.type | IN("completed","canceled") | not))
  | "\(.identifier) estimate未設定 \(.title[0:40])"'

# 9) Projectのオーバービュー（週1回でよい。月曜のCycle計画時が目安）
#    projects と issues を1クエリにまとめると "Query too complex" で弾かれるので分ける
linear_gql '{ projects(first: 50) { nodes { id name state targetDate } } }' > /tmp/pj.json
linear_gql '{ issues(first: 250) { nodes { project { id } state { type } } } }' > /tmp/iss.json
jq -r --arg t "$(date +%F)" --slurpfile iss /tmp/iss.json '
  ($iss[0].issues.nodes) as $I |
  .projects.nodes
  | map(. as $p | {name, state, targetDate,
      open: ([$I[] | select(.project.id == $p.id and (.state.type|IN("completed","canceled")|not))]|length)})
  | sort_by(.state != "started", .name)[]
  | "\(if .state=="started" then "▶" else " " end) \(.name)  \(.state)  open=\(.open)  target=\(.targetDate // "未設定")\(if .targetDate!=null and .targetDate<$t then " ⚠超過" else "" end)\(if .open==0 then " ⚠open0件" else "" end)"' /tmp/pj.json
```

4件目（My Reviewの混入）の打ち手は、**行き先を1つ決めて動かす**。`My Review` は
AIの成果物を四択で裁く場所なので、自分が手を動かしている課題を置くところではない。

| 実態                                       | 行き先                          |
| ------------------------------------------ | ------------------------------- |
| まだ自分で作業している（整理・実装・確認） | `In Progress`                   |
| 他人・CI・返信を待っている                 | `Waiting`                       |
| 終わっている                               | `Done`                          |
| AIに実装させたい                           | `AI Queued`（`repo:` 行を足す） |

EMレーンの成果物（`01_Inbox/ai/` 配下の叩き台）に対しては、四択を次のように読み替える。

| 実装レーン       | EMレーン                                                |
| ---------------- | ------------------------------------------------------- |
| マージ           | そのまま場に出す                                        |
| チームレビューへ | 関係者に投げる                                          |
| 修正指示         | 質問に答えて再投入（`/nippo-add こたえ: <identifier>`） |
| 破棄             | 破棄                                                    |

Projectで見るのは3点。

| 症状                          | 意味                                              | 打ち手                                                                                                   |
| ----------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| **open 0件**                  | 中身が無いのにProjectだけ存在する                 | 完了なら `completed`、やらないなら削除。「いつかやる」なら `Planned` のまま置いてよいがtarget dateは外す |
| **target未設定**              | 「期限のある塊」というProjectの定義から外れている | 期限を入れるか、期限が決められないなら常設カテゴリ化しているサインなので分割・削除を検討                 |
| **In Progress が4つを超える** | 並行しすぎ                                        | どれかを `Planned` に戻す                                                                                |

Cycleの2件（7・8）で見るのは次のとおり。

| 症状               | 意味                                                          | 打ち手                                                                                                                                                               |
| ------------------ | ------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **親子の二重計上** | velocityが二重に数えられ、「今日やる3件」に親と子が並んで出る | 親をCycleから外す（`issueUpdate(cycleId: null)`）。親の期限はProjectのtarget dateで追う                                                                              |
| **estimate未設定** | 「今日どれだけ入るか」が計算できない                          | Cycle計画時に入れる。ただし**velocityが2〜3サイクル溜まるまでポイントを時間に換算しない**（fibonacciは相対見積もりなので、実績が無いうちに換算すると嘘の数字になる） |

見つかったものは**その場で直さず報告する**。親子の取り残しは「子も閉じる」か「親から切り離して
単独の課題にする」かで判断が分かれるため、人間に聞く。Cycleの二重計上は打ち手が一意だが、
「親のほうを残して子を外す」を選びたい場合もあるので同じく確認を取る。

### 2. Triageを受け入れる（あれば）

Triageは**機械が拾ったものの受信箱**。スイープが起票したdraft PRが入っている。
1件ずつ以下を決めて、`Todo` か `Canceled` へ送る。

- 既存の親課題にぶら下げる（`parentId` を設定）
- 新しい親課題を作る（`/linear-add` の規約に従う。Jiraキーがあれば拾う）
- やらないので `Canceled`

**親の単位はJiraが決める。** 複数PRを1つの親にまとめる前に、各PRのJiraキーが同一かを
`gh pr view <番号> --repo <owner/repo> --json title,headRefName` で確認する。
ブランチ名にキーが入っていることが多い。

### 3. 今夜AIに投げる候補をスコアリングする

`Todo` から、`ai:blocked-human` が付いていないものを対象に3軸で評価する。

| 軸               | 高い条件                                                                                                                             |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| **緊急度**       | `dueDate` が近い／超過している。`createdAt` からの滞留日数が長い                                                                     |
| **AI委譲可能度** | 自己完結して検証可能（テスト・lint・ビルドで成否が決まる）。コード変更を伴う実装・リファクタ・調査は高い。関係者調整・意思決定は低い |
| **人間判断残量** | 朝の判断が「diffを見てマージ可否を決めるだけ」に近いほど高い                                                                         |

**子の緊急度は親の `dueDate` を継承して評価する。**
期日はJira由来なので**親（課題）にしか付かない**が、dispatchできるのは `repo:` 行を持つ
**子（工程）**。素直に子の `dueDate` だけを見ると、いちばん急ぐ仕事が候補から漏れる。

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"
linear_gql '{ issues(first: 100, filter: {state: {type: {nin: ["completed","canceled"]}}}) {
  nodes { identifier title dueDate createdAt
          parent { identifier dueDate }
          labels { nodes { name } } } } }' \
| jq -r --arg t "$(date +%F)" '
  [.issues.nodes[]
   | select((.labels.nodes|map(.name)|index("ai:blocked-human")) == null)
   | . + {eff_due: (.dueDate // .parent.dueDate)}
   | select(.parent != null)]                       # dispatch対象は子だけ
  | sort_by(.eff_due // "9999-99-99")
  | .[] | "\(.identifier)\tdue=\(.eff_due // "-")\t\(if (.eff_due // "9999") < $t then "超過" else "  " end)\t\(.title[0:40])"'
```

- **`draft仕上げ:` の子issueは有力候補**。draft PRという成果物が既にあり、残りが仕上げだけのことが多い
- **`実装:` の子issueはゼロから書かせる**ので、指示が粗いと空振りする。`draft仕上げ:` より慎重に選ぶ
- **親課題（課題そのもの）は投げない**。成果物を持たないので `repo:` 行が書けない
- 思考タスク（体制の構想・意見のまとめ・概念整理）は **`ai:blocked-human` を付けて対象外にする**。
  AIに投げても人間の判断が全部残るため、夜間に回す意味がない

上位3件（`LINEAR_DISPATCH_MAX` と同数）を表で提示し、AskUserQuestionで選択を求める。
スコアの根拠（期日・滞留日数・なぜ委譲できると判断したか）を必ず添える。

### 4. 承認されたissueを整形する

dispatchの起動条件は **state = `AI Queued`** の1点（ラベルは見ない）。
パイプライン上の位置はstateで表し、ラベルと二重に持たない。

**dispatchは本文の内容で2モードに分かれる。整形時にどちらになるかを意識する。**

| 本文              | モード | dispatchの動作                                           |
| ----------------- | ------ | -------------------------------------------------------- |
| 既存PRのURLがある | 継続   | そのPRのブランチで作業。**新規PRは作らない**             |
| `repo:` 行のみ    | 新規   | `linear/<identifier>` ブランチを切って新規draft PRを作る |

**タイトルのprefixとモードは対応している。** `draft仕上げ:` は `元URL:` に既存PRを持つので
**自動的に継続モード**になる（`repo:` 行を足す必要はない。足しても継続モードが優先される）。
`実装:` は `repo:` 行だけを持つので新規モードになる。
継続モードはPRが `OPEN` でなければ差し戻される。

prefixと本文が食い違っている issue（`draft仕上げ:` なのにPR URLが無い等）を見つけたら、
整形のついでにタイトルを直す。モードの判別ができなくなるため。

本文を以下の形にして、**人間に見せて添削を受けてから** `AI Queued` へ遷移させる。

継続モード（既存PRの仕上げ）:

```
元URL: <PRのURL>

## AIへの指示

<残っている作業。レビュー指摘への対応、テスト追加、など>

## 検証方法

<テストコマンド・確認手順>
```

新規モード（ゼロから実装）:

```
repo: github.com/<owner>/<name>

期待アウトカム: <元の記述を保持>

## AIへの指示

<具体的な作業指示。対象ファイル・実装方針・完了条件>

## 検証方法

<テストコマンド・確認手順>
```

- **`repo:` は行頭に書く**（新規モードのみ）。dispatchは `^repo:` の行頭一致で読む
- **`repo:` の値は子の元URL（PR URL）から機械的に導ける。** スイープが起票した子は
  `元URL: https://github.com/<owner>/<name>/pull/<n>` を持つので、そこから切り出す

  ```bash
  sed -E 's#.*(github\.com/[^/]+/[^/]+)/pull/.*#\1#'
  # https://github.com/example-org/example-repo/pull/11087 → github.com/example-org/example-repo
  ```

- **repoがローカルに実在するか確認する**（`ls "$(ghq root)/github.com/<owner>/<name>"`）。
  無ければ整形せず報告する。dispatchはworktreeを作れず差し戻す
- Linearは `github.com/...` を自動でmarkdownリンク化するが、dispatch側のパーサは
  リンク記法に対応済みなのでそのままでよい

指示は**AIが単独で完遂できる粒度**まで具体化する。曖昧なまま投げると、翌朝
「何をどう判断すればいいか分からないdraft PR」が増えて判断コストが上がる。

### 5. 最後に確認を出す

- 今夜投げる件数と、それぞれの期待アウトカム
- 「My Review」の見込み件数（現在＋今夜の投入数）がWIP上限を超えないか

## 注意

- このskillは**起票しない**。新規タスクの起票は `/linear-add`
- `dueDate` はJiraが持つ。Linear側で勝手に日付を作らない
- 夜間dispatchは現在 **cron未登録**（数日運用してから判断する方針）。`AI Queued` に置いても
  自動では走らない。試すなら `env LINEAR_DISPATCH_MAX=1 bash ~/scripts/linear/dispatch-cron.sh`
