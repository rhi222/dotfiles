---
name: kb-harvest
description: 1日のClaude/Codex sessionを振り返り、memoryではなくナレッジベース（Obsidian vaultとglossary）に残すべき知識の候補を拾って、承認されたものだけ書き込む。「KBに貯めて」「今日のsessionからナレッジを拾って」「kb-harvest」「ナレッジ化」などで使用。
disable-model-invocation: true
argument-hint: "[日付 YYYY-MM-DD] (省略時は本日)"
allowed-tools: Read, Write, Edit, Agent, Bash(dotctl:*), Bash(rg:*), Bash(date:*), Bash(source:*), Bash(ghq:*), Bash(mktemp:*), Bash(ls:*)
---

# kb-harvest

その日のsessionから、他の人や他リポジトリのAIが読んでも価値のある知識を拾い、
承認されたものだけをvaultとglossaryへ書き込む。設計は `docs/kb-harvest.md`。

## 前提

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/nippo-paths.sh"
TARGET_DATE="$(nippo_resolve_date "${ARGUMENTS:-}")"
VAULT="$(nippo_vault)"
GLOSSARY="$(ghq root)/github.com/rhi222/dotfiles/.config/agents/skills/glossary/glossary.md"
DIGEST_DIR="$(mktemp -d)"
dotctl session digest --date "$TARGET_DATE" --out-dir "$DIGEST_DIR"
```

**Bashの呼び出しをまたいでシェル変数は残らない。**
このブロックは1回のBash呼び出しで実行し、`TARGET_DATE` `VAULT` `GLOSSARY` `DIGEST_DIR` の値を
`echo` で出して控える。以降の手順では控えた実際のパスを直接書く。

stdoutの索引が0行なら「対象なし」と伝え、手順7の後片付けをしてから終わる。
stderrに `session-digest: SKIPPED=N UNREADABLE=M` が出たら、件数だけ利用者に伝えて続ける。
`UNREADABLE` は開けなかったログファイルの数で、そのsessionは判定から漏れている。

## 手順

1. **判定を並列に投げる。** 索引の `file` を、`chars` の合計がおよそ8万字を超えないように束ね、
   1束につきsubagentを1つ起動する。1 sessionだけで8万字を超えるものは単独で1束にする。
   すべて1つのメッセージで同時に起動する。
   - prompt: `judge.md` の全文と、担当するdigestファイルのパスの一覧
   - **digest本文をこのsessionで読まない。** 読むとコンテキストが溢れる
2. **返答を検査する。** JSONとして読めない返答は、その束のsessionを「判定失敗」として一覧の末尾に出し、残りは続ける。
   束に渡したsessionが `results` に欠けていたら、そのsessionも「判定失敗」に入れる
3. **vaultと突き合わせる。** 候補ごとに `title` と主要な語で `rg -l` を掛ける
   - `term`: `$GLOSSARY` の見出しと `別名:`
   - `system` / `org`: `$VAULT/03_Product` `$VAULT/05_Organization` `$VAULT/06_Domain`
   - 同じ内容が既にあれば一覧から外す。同じ主題のノートがあれば「追記」、無ければ「新規」にする
4. **提示する。** 次の形の一覧を出し、採用する番号を聞く。候補が5件以下なら各候補の本文も示す

   ```text
   [1] term / 新規     「用語」 … 意味の1行         → glossary.md
   [2] system(project) / 追記   見出し …            → 06_Domain/<project>/<note>.md
   [3] org / 新規      見出し …                     → 05_Organization/<note>.md
   [4] skill           「依頼の文面」×4回           → /session-patterns で深掘り
   採用する番号（例: 1,3 / all / none）
   ```

5. **承認された分だけ書く。**
   - `term`: `glossary` skillの「追記する」の規則に従い、`$GLOSSARY` の末尾へ書く。`$GLOSSARY` が無ければ書かずに本文を示すだけにする
   - `system` / `org` の新規: 置き場候補のディレクトリの既存ノートの書式（Frontmatter、見出し、Wiki Link）に合わせて作る。置き場が判断できなければ `$VAULT/01_Inbox/` に置く
   - `system` / `org` の追記: 既存ノートの**末尾にだけ**節を足す。既存の本文は書き換えない
   - 出典に `session <session_id>（<TARGET_DATE>）` を書く。`term` は `- 出典:` 項目に、`system` / `org` は書いた節の末尾に付ける
   - `term` の詳細を同じ回に `system` ノートへ書いたなら、glossary の意味は短くし `- 詳細:` からそのノートを指す
   - `skill`: 書かない
6. 書いたファイルの一覧を出す。commitはしない
7. **digestを後片付けする。** digestは会話本文の写しなので残さない。
   判定に失敗した束があっても、書き込みを中断したときも、最後に必ず
   `dotctl session digest-clean <控えたDIGEST_DIRのパス>` を実行する

## やってはいけないこと

- 承認されていない候補を書く
- vaultとglossary以外へ書く（Slack、Jira、esa、GitHubを含む）
- 人事・評価・候補者の情報を書く
- 既存ノートの移動、名前変更、本文の書き換え
