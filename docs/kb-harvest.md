# kb-harvest

1日のClaude/Codex sessionから、memoryではなくナレッジベースに残すべき知識を拾う仕組み。
入口はClaude専用skill `/kb-harvest [YYYY-MM-DD]`。

## 判断

- 置き場は個人のObsidian vaultと `glossary.md`。
  自動判定には誤検出が出るので、共有リポジトリへは直接書かない。
  育ったものは人が各リポジトリやesaへ昇格させる。
- 起動は手動。
  精度が分からないうちにcron化すると、読まれない候補レポートが溜まる。
  精度が見えたら、夜間cronで候補だけを `01_Inbox/ai/` に作る形へ移す。
- 書き込みは承認制。既存ノートへは末尾追記だけにする。
- memoryとの境界は「他の人や他リポジトリのAIが読んでも価値があるか」。
  AIへの作業上の指示はmemory、その日の作業状況は日報に残す。

## 部品

| 部品     | 場所                                                 |
| -------- | ---------------------------------------------------- |
| digest   | `dotctl session digest`（`internal/sessiondigest/`） |
| skill    | `.config/claude/skills/kb-harvest/`                  |
| 判定基準 | `.config/claude/skills/kb-harvest/judge.md`          |

## digestが捨てるもの

tool_use、tool_result、thinking、`isMeta` の行、subagent（sidechain）のログ、Codexのdeveloperロールを捨てる。
userロールの本文のうち、`<` で始まるもの（`<system-reminder>` など）と、AGENTS.mdやskill本文の注入も捨てる。
残すと1 sessionが数十万字になり、判定が注入文を知識と取り違える。

当日より前に更新が止まったログファイルは開かない。
Codexのrolloutは開始日のディレクトリに置かれたまま、resumeで追記される。
そのため全日付のディレクトリをglobし、当日に更新されていないファイルはmtimeで飛ばす。
Claudeはファイル名のuuidをsession idにする。
resumeやforkをしたログは、先頭行の `sessionId` が元sessionのままのことがあり、digest名が衝突するため。
compact後の要約（`isCompactSummary`）は前日以前の内容を含むので捨てる。

## 既知の限界

- `<` で始まる本文はHTMLの貼り付けでも捨てる。取りこぼしが問題になったら、既知のタグ名に絞る。
- 処理済みsessionの台帳は持たない。同じ日を再実行すると、vaultとの突き合わせで重複として落ちる。

## 導入

マージ後に `dotctl rebuild` を実行する。
古いバイナリは `session digest` を知らず、終了コード2で止まる。
