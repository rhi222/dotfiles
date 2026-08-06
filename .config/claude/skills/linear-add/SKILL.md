---
name: linear-add
description: Linear（linear.app/nsym・team NSY）にタスクを起票する。prefix判定・Project選択・親子構造・Jira番号抽出・ラベル付与を規約どおりに自動適用する。「Linearに起票」「これチケット化して」「タスク積んで」「issue作って」やPR/JiraのURLを渡された文脈で使用。
argument-hint: "<やること、またはPR/JiraのURL>"
allowed-tools: Read, Bash(bash:*), Bash(source:*), Bash(jq:*), Bash(gh:*), Bash(grep:*), Bash(sed:*), Bash(date:*)
---

# Linearへの起票

タスク管理はLinear（https://linear.app/nsym・team `NSY`）に集約している。
**Linearは真実の源泉ではなく「ポインタの司令塔」**で、issueは元URL＋期待アウトカム＋判断状態だけを持つ。
本体はJira / GitHub / Slack / esa 側にある。

設計の全体像とその根拠は `~/Obsidian/01_Inbox/2026-08-06-linear-command-layer-design.md`。
このskillはそこで決めた規約の**運用手順**を持つ。矛盾したら設計docが正。

## 使うライブラリ

`$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh` を source して使う。

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"
linear_issues_in_state "Todo"
linear_issue_create "<title>" "<description>" "<state名>" "<label名>..."
linear_issue_move "<issueId>" "<state名>"
linear_comment "<issueId>" "<body>"
linear_gql '<query>' '<variables-json>'
```

`linear_issue_create` は assignee を自動で自分にする（未アサインだと My Issues に出ない）。
Project・親子・複数ラベルを一度に設定したい場合は `linear_gql` で `issueCreate` を直接叩く。

## 絶対に守ること

**GitHub / Jira へ書き戻さない。** リンクは Linear → 外部の一方向のみ。
外部issue・チケットへのコメント／ラベル付与／ステータス変更をしない。
「LinearのNSY-Xと紐づけました」のような紐づけコメントも禁止。
`gh` は `view` / `search` などの読み取りだけを使う。

## 手順

### 1. 入力から材料を集める

URLが渡されたら読み取って情報を補う（読み取りのみ）。

- **GitHub PR** → `gh pr view <番号> --repo <owner/repo> --json title,body,headRefName`
  - タイトル・本文・ブランチ名から `[A-Z][A-Z0-9]+-[0-9]+` を拾ってJiraキー候補にする
  - **`AP3-001` のような仕様書の項番を拾うことがある。** 実在するJiraプロジェクトキー（`ALPHADEV` / `BETADEV` など）か確認し、怪しければ採用せず利用者に確認する
  - `example-api` はJira管理外（GitHub issueで管理）。Jiraキーが無くても異常ではない
- **Jira URL** → キーとタイトルを取る。Jira APIの認証情報は無いので、URLからキーだけ抜き、タイトルは利用者に聞くか本文から推測する
- **Slack / esa URL** → そのまま元URLとして持つ

### 2. Projectを決める

既存Projectを一覧して、該当するものがあれば選ぶ。

```bash
linear_gql '{ projects(first: 50) { nodes { id name state } } }'
```

新規に作る場合、**prefixは判定順で決める（先に当たった方が勝ち。MECEにしない）**。
判定するのは**動機ではなく成果物**。

| 順 | prefix | 判定の問い |
| --- | --- | --- |
| 1 | `案件_` | 特定の顧客案件のためだけの仕事か（その案件が終われば消える） |
| 2 | `技術採用_` | 採用活動そのものか（候補者を探す・口説く・選ぶ） |
| 3 | `組織課題_` | 対象がヒトか（体制・育成・評価・自分の働き方。採用活動以外） |
| 4 | `QA_` | 品質の確かめ方が変わるか（テスト・検証・レビュー） |
| 5 | `プロダクト開発_` | 作るもの・作り方が変わるか（機能・設計・リリース・基盤・ドメイン整理） |
| 6 | `other_` | どれでもない（受け皿） |

- 「リリースプロセスの標準化」は手順の話なので4で止まらず `プロダクト開発_`
- 「リリース前後の回帰試験自動化」は検証なので `QA_`
- 「成長に応えるリアーキテクト」は動機がヒト側でも成果物はコード構造なので `プロダクト開発_`
- **Projectは常設カテゴリではなく「着地点と期限のある塊」**。target dateを付ける
- **In Progress は4つまで**。超えるなら新規は `Planned` で作る
- 自分がドライブしていない（レビュアー・相談役）ものはProject化せず、Project無しのissueにする

### 3. 親子を決める

| 階層 | 単位 | 持つもの |
| --- | --- | --- |
| 親issue | 1課題（Jiraチケットと1:1） | Jira番号 / role / em / Project |
| 子issue | 工程 | `repo:` 行（夜間dispatch対象） |

- **PRを伴う課題は1PRでも親子に分ける**（PRの本数はあとから増えるため）。子のタイトルは `draft仕上げ: <PRタイトル>`
- **PRを伴わない思考タスクは親1枚**（体制の構想、意見のまとめ、概念整理など）。工程が出たら後から子を足す
- 子は都度必要なものだけ。定型4工程（実装／レビュー依頼／社内連絡／リリース）を空で並べない

### 4. ラベルを付ける（role と em を必ず1つずつ）

2軸は直交する。`role:player + em:tech`（自分で実装した）と `role:manager + em:tech`（技術方針を決めた）を区別する。

| group | label | 意味 |
| --- | --- | --- |
| role | `role:player` | 自分が手を動かす |
| role | `role:manager` | 人を動かす・決める |
| em | `em:people` | 人・採用・育成・評価・体制 |
| em | `em:tech` | 技術方針・設計・実装・基盤・品質 |
| em | `em:project` | 進行・段取り・リスク・調整 |
| em | `em:product` | 何を作るか・仕様・ドメイン・価値 |
| src | `src:github` / `src:jira` / `src:slack` / `src:esa` / `src:todoist` | 流入元（該当すれば付ける） |
| ai | `ai:ready` | 夜間dispatchに投げられる状態（このskillでは付けない。triageで付ける） |
| ai | `ai:blocked-human` | 人間の判断・調整が必要 |

draft PRの仕上げは常に `role:player` + `em:tech`。

### 5. stateを決める

| state | 使いどころ |
| --- | --- |
| `Triage` | **機械が拾ったものだけ**。手動起票では使わない |
| `Todo` | 今のサイクルでやる |
| `Backlog` | 棚上げ。やると決めきれていない |

### 6. 本文を書く

**案件系の親課題**はテンプレートに従う（Linearのissue template `親課題（案件）` と同じ形）。

```
jira: <URL。無ければ空でよい>

完了条件: <何ができたら閉じるか。1行>

slack:

- (スレッドURL)

PR:

- <PR URL>

メモ: <補足>
```

それ以外は最低限これを書く。

```
元URL: <あれば>

期待アウトカム: <何ができたら完了か>

滞留開始: <日報から移行した場合のみ YYYY-MM-DD>
```

**`完了条件` / `期待アウトカム` は必ず埋める。** 日報から移行した滞留25件を棚卸ししたとき、
1ヶ月動かなかった5件は全て「期待アウトカムが書かれていない」issueだった。
終わりが定義されていないタスクは着手されない。
利用者が言語化できない場合は、それ自体が「やると決まっていない」証拠なので `Backlog` に置く。

**タイトル規約**: 親課題でJiraチケットがある場合は `{jiraチケット名称} [ALPHADEV-1234]`。
半角スペースを1つ空けて角括弧。Jiraが無い課題には付けない（組織課題・自主的なリファクタなど）。

### 7. 起票して結果を報告する

identifier と URL を返す。複数件なら表で出す。

## Linear markdownの罠

- **空の `- ` 行を書くと直前の行がH2見出しになる**（setext heading `text\n---` と誤認される）。箇条書きにはプレースホルダを残す
- **`\n` 単発はsoft breakとして1段落に連結される**。項目を分けるには**空行**が要る
- LinearはURLを自動でmarkdownリンク化する（`[url](<url>)`）。本文からURLを抜くときは
  `grep -oE 'https://[^)>[:space:]]+'` ではなく、リンク記法を考慮した正規表現を使う

## 確認を取るべきとき

以下は勝手に決めず利用者に聞く。

- Jiraキーが複数見つかった、または実在するプロジェクトキーか確信が持てない
- 新規Projectを作る必要がある（判定順は適用したうえで、名前と target date を確認する）
- 既存の課題に紐付くのか、新しい課題なのか判別できない
- `完了条件` を利用者に書いてもらう必要がある
