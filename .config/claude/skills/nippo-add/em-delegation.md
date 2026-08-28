# EMタスクをCodexに任せる候補を出す

新規日報作成時に、`role:manager` のissueから「Codexに叩き台を作らせる候補」を提示し、
承認を取ってEMレーンへ投入するためのロジック。

**起票と実行はスクリプトに任せる。** 判断（どれを候補にするか）だけをここで行い、
state遷移とワーカー起動は `em-dispatch.sh enqueue` が担う。
`interview-prep.sh` と同じ役割分担。

## 候補の選び方

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"
linear_cycle_issues | jq '[.[]
  | select(.state.name | IN("Todo","In Progress"))
  | select((.children.nodes | length) == 0)
  | select([.labels.nodes[].name] | index("role:manager"))
  | select([.labels.nodes[].name] | index("ai:blocked-human") | not)
  | select((.description // "") | test("(?m)^repo:") | not)
  | select(.estimate == 2 or .estimate == 3)]'
```

条件の理由。

| 条件 | 理由 |
| --- | --- |
| `Todo` / `In Progress` | ボールが自分にあるもの。`Waiting` は他人、`AI Queued` は既に投入済み |
| 子issueを持たない | 実作業単位。親を投げると粒度が粗すぎる |
| `role:manager` | EMレーンの対象。`role:player` は実装レーンが夜間に拾う |
| `ai:blocked-human` を持たない | 対人そのもので委譲できない（NSY-112など） |
| `repo:` 行が無い | あると実装レーンの担当になる |
| estimate が `S`(2) か `M`(3) | `L`(5) は「分割しろ」の印なのでそのまま投げない |

優先順は、期日超過（`dueDate` が今日より前）→ `createdAt` が古い → `em:*` ラベルの
手薄な軸。**最大3件**に絞る。

アクティブなCycleが無い週は `linear_issues_in_state "Todo"` に同じフィルタをかける。
Linearにアクセスできない場合はセクションごと省略し、日報作成を続行する。

## 承認を取る

`AskUserQuestion` で候補を提示する。`multiSelect: true` にして、任せるものだけを選ばせる。
選ばれなかったものは**stateを一切動かさない**（`Todo` のまま残す）。

質問文には各候補の identifier・タイトル・滞留日数を入れる。

## 投入する

承認されたものだけ、まとめて1回で渡す。

```bash
bash "$(ghq root)/github.com/rhi222/dotfiles/scripts/linear/em-dispatch.sh" \
  enqueue NSY-12 NSY-92
```

出力は `<identifier>: QUEUED` か警告。`enqueue` は `AI Queued` への遷移と
ワーカーの切り離し起動までを行い、即座に戻る。**完了を待たない。**

`em-dispatch.sh` が無い・Linearにアクセスできない場合は、候補提示だけ行って
投入をスキップし、日報作成を続行する。

## 未回答の質問を朝に出す

前回までのEMレーンの成果物のうち、まだ回答していないものを日報に出す。
質問はLinearのコメントにあるが、**朝に目に入る場所が要る**ので日報へ転記する。

`My Review` のissueのうち、状態ディレクトリに出力JSONが残っているものが対象。

```bash
STATE_DIR="${LINEAR_EM_STATE_DIR:-$HOME/.local/state/linear-em-dispatch}"
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"
linear_issues_in_state "My Review" \
| jq -r --arg d "$STATE_DIR" '.[] | .identifier' \
| while read -r id; do
    [[ -f "$STATE_DIR/$id.json" ]] && echo "$id"
  done
```

各issueについて、質問の**本文は出さず件数と成果物パスだけ**を出す。全文を日報に
貼ると長くなりすぎるうえ、回答は `/nippo-add こたえ:` で `AskUserQuestion` を使うため。

```markdown
## AIからの質問

> `/nippo-add こたえ: <identifier>` で回答する

- NSY-12 予約のコア/カスタマイズ/拡張 分類案をつくる — 質問3件 / `01_Inbox/ai/NSY-12-分類案.md`
```

対象が0件ならセクションごと省略する。

## 朝の判断タイムの読み替え

`My Review` にEMレーンの成果物が混ざるので、四択の文言を読み替える。
日報の「朝の判断タイム」行はそのままにし、EMレーン分については次の対応で裁く。

| 実装レーン | EMレーン |
| --- | --- |
| マージ | そのまま場に出す |
| チームレビューへ | 関係者に投げる |
| 修正指示 | 質問に答えて再投入（`/nippo-add こたえ:`） |
| 破棄 | 破棄 |

## 日報への書き方

`## 今日のおすすめタスク` の直後に置く。対象が1件も無ければセクションごと出さない。

```markdown
## AIに任せる候補

> Codexが叩き台と確認質問を作る。完了するとLinearの My Review に入る

- [x] NSY-12 予約のコア/カスタマイズ/拡張 分類案をつくる（滞留21日）→ AI Queued
- [ ] NSY-92 シニア採用KPIの部としての内訳と予算影響を提案する（滞留17日）→ 見送り
```
