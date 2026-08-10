---
name: linear-slack-sweep
description: Slackで特定のスタンプ（既定 :nishiyama_todo:）を押したメッセージを拾い、LinearのTriageへ起票する。「Slackのスタンプを拾って」「スタンプ起票」「slack sweep」「Slackから起票して」などで使用。cronからもヘッドレスで呼ばれる。
allowed-tools: Bash(date:*), Bash(scripts/linear-slack-sweep.sh:*), mcp__claude_ai_Slack__slack_search_public_and_private, mcp__claude_ai_Slack__slack_read_thread
---

# Slackのスタンプから Linear へ起票する

Slack上で「これタスクだ」と気づいた瞬間にスタンプを押すだけで、Linear の Triage に
ポインタが積まれるようにする。判断（要約とタイトル生成）だけをここで行い、
状態変更（重複チェック・起票・処理済み記録）は `scripts/linear-slack-sweep.sh` に任せる。

**Slackへは一切書き込まない。** リンクは Linear → Slack の一方向のみ。
Slackはチームの共有物なので、個人のタスク管理都合のノイズを持ち込まない。
このskillには読み取りツールしか許可されていない。

## 設定

| 変数 | 既定値 | 意味 |
| --- | --- | --- |
| `LINEAR_SLACK_EMOJI` | `nishiyama_todo` | 起票トリガのスタンプ名 |
| `LINEAR_SLACK_SWEEP_DAYS` | `14` | 検索の遡り日数 |
| `LINEAR_SLACK_SWEEP_MAX` | `20` | 1回で処理する上限（`unseen` が担保する） |

## 手順

### 1. 候補を検索する

遡り日数から検索の起点を作る。

```bash
date -d "${LINEAR_SLACK_SWEEP_DAYS:-14} days ago" +%F
```

`mcp__claude_ai_Slack__slack_search_public_and_private` を呼ぶ。

- `query`: `hasmy::<EMOJI>: after:<上で求めた日付>`
- `sort`: `timestamp`
- `include_context`: `false`
- `limit`: `20`

結果が20件なら `cursor` で次ページも取る。

**検索窓は固定の遡り日数にしていて「前回実行日」を持たない。** 処理済み記録が
冪等性を担保するので、同じ期間を何度スキャンしても二重起票にならない。
cronが落ちた日があっても次回が勝手に拾い直す。

ヒット0件ならここで終了し、`起票対象なし` とだけ報告する。

### 2. 処理済みを落とす

各ヒットから `<channel_id>/<message_ts>` の形のキーを作る（検索結果の `Channel: ... (ID: Cxxx)`
と `Message_ts:` から組む）。まとめてスクリプトに渡し、残ったものだけを次へ進める。

```bash
scripts/linear-slack-sweep.sh unseen "C123/1786335015.733309" "C456/1786111487.003049"
```

**スレを読む前にここで絞る。** 読解コストが一番高いので、関門を手前に置く。
出力が空なら `新規なし` と報告して終了する。

### 3. スレを読む

残ったキーごとに `mcp__claude_ai_Slack__slack_read_thread` を呼ぶ。

- `channel_id`: キーの前半
- `message_ts`: 検索結果のpermalinkに `thread_ts=` があればその値、無ければキーの後半
- `response_format`: `detailed`（`Reactions:` を得るため）

読んだら**2つのことをする**。

1. **リアクションの実在を確認する。** 対象メッセージの `Reactions:` に `<EMOJI>` が
   居なければ**スキップする**（起票しない）。Slack検索は絵文字名が実在の英単語のとき
   本文にもフォールバックするため、これが誤検知の最終防壁になる。
   スキップしたキーは処理済みにせず、次回また評価させる
2. **スレ全体を文脈として読む**

### 4. 起票する

スレから3つを作る。

| 項目 | 作り方 |
| --- | --- |
| タイトル | 「何をするのか」が動詞で分かる1行。Slackの発言をそのまま切らない |
| 期待アウトカム | 「何ができたら終わりか」の1行 |
| 経緯 | スレの要約。3行以内 |

**prefixは付けない。** `draft仕上げ:` はdraft PRが実在するもの、`実装:` はPRがまだ無い工程に
使う語で、Slack起点のものはどちらでもない。分類は朝のtriageで人間が決める。

キーごとに1回呼ぶ。

```bash
scripts/linear-slack-sweep.sh create "<key>" "<permalink>" "<タイトル>" "<期待アウトカム>" "<経緯>"
```

スクリプトが返すのは次のいずれか。

| 出力 | 意味 |
| --- | --- |
| `created NSY-xxx` | 新規に起票した |
| `commented NSY-xxx` | 同じスレのissueが既にあったのでコメントを足した |
| `skipped(seen) <key>` | 既に処理済みだった |

### 5. 報告する

起票した件数と、`NSY-xxx / タイトル` の一覧を出す。
リアクション不在でスキップしたものがあれば件数を添える。

## やらないこと

- **Slackへの書き込み**（返信・スタンプ・canvas）
- **ラベルは `src:slack` のみ。** `role:*` / `em:*` と Project は朝のtriageで人間が決める。
  Jiraスイープが role/em を付けないのと同じ扱い
- **Triage以外のstateへの起票。** Triageは「人間が選別する受信箱」なので、そこを迂回しない
