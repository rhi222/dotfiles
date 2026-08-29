---
name: linear-recall
description: SlackスレのURLやキーワードから、既にLinearに起票済みのissueを探して思い出す。「これ起票済み？」「NSY-xxxにあったはず」「このスレのチケットある？」「Linearに既にある？」などで使用。起票はしない（起票は linear-add）。
argument-hint: "<SlackスレのURL、またはキーワード>"
allowed-tools: Read, Bash(bash:*), Bash(source:*), Bash(jq:*)
---

# 起票済みのissueを思い出す

Slackのスレッドでメンションされたとき「これは起票済みのNSY-xxxにあったはず」を解決する。
**起票はしない。** あるかどうかを答えるのが仕事で、無かったら `/linear-add` に渡す。

APIレシピは `.config/claude/skills/linear-add/references/api-recipes.md` を読むこと
（`linear-add` の重複チェックと同じクエリを使う）。

## 検索の強さを混同しない

| 入力           | 検索                                                     | 強さ                          |
| -------------- | -------------------------------------------------------- | ----------------------------- |
| SlackスレのURL | `searchableContent: {contains: "/archives/<CID>/p<TS>"}` | **確定**（元URLとの完全一致） |
| キーワード     | `searchIssues(term:)`                                    | **候補**（人間の確認が要る）  |

**この2つを出力で必ず区別する。** 候補を確定のように出すと、
実在しないissueを「ある」と信じて二重起票する事故につながる。

## 手順

### 1. 入力を判別する

SlackのURL（`https://<team>.slack.com/archives/<CID>/p<TS>...`）が渡されたか、
それ以外のキーワードかで分岐する。URLなら `?` 以降を落として
`/archives/<CID>/p<TS>` の部分だけを取り出す。

### 2. URL一致で探す（URLが渡された場合）

`api-recipes.md` の「重複チェック」のクエリを、抽出した中核部分で実行する。
`includeArchived: true` を必ず付ける。

ヒットしたら **確定** として報告し、ここで終わる。

### 3. キーワードで探す

URLが渡されなかった場合、またはURL一致が0件だった場合に実行する。

**URL一致が0件でも止めない。** 起票時に元URLを入れそこねた分、Jira経由で起票した分は
URLでは絶対に当たらないため、必ずキーワード検索に落とす。

キーワードは入力から作る。URLしか渡されていない場合は、そのスレの話題を
利用者に一言で聞いてから検索する（Slackを読む権限はこのskillに無い）。

### 4. 報告する

ヒットあり:

```
確定（元URL一致）
- NSY-42 PMS疎通試験の結果をまとめる [In Progress] https://linear.app/nsym/issue/NSY-42
```

```
候補（キーワード一致・要確認）
- NSY-42 ... [Done] ...
- NSY-77 ... [Todo] ...
```

ヒット0件:

**「起票されていない」と言い切る。** 濁さない。そのうえで `/linear-add` に渡せるよう、
元URLと分かっている材料を並べて提示する。

## やらないこと

- **起票**（`/linear-add` の仕事）
- **Slackを読むこと**（このskillに権限は無い。スレの中身が要るなら利用者に聞く）
- **候補と確定を混ぜて出すこと**
