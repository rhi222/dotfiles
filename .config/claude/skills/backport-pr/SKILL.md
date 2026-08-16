---
name: backport-pr
description: 既にあるPRと同じ変更を、別のベースブランチ向けのPRとして作り直す。「main向けPRも作成して」「◯◯ブランチにも取り込んで」「このPRを別ブランチにも入れたい」「同じ修正を両方のブランチに」などで使用。長命ブランチが並走しているリポジトリで、片方に入れた修正をもう片方へ持っていくときは、backportという語が出ていなくてもこのスキルを使う。新規実装からPRを作る場合は wt-pr を使う。
argument-hint: "<元PR（URLまたは owner/repo#番号）> <移植先ブランチ>"
allowed-tools: Bash(gh:*), Bash(git:*), Read
---

# 既存PRを別ブランチへ移植する

案件別ブランチと `main` のように長命ブランチが並走しているリポジトリでは、
片方に入れた修正をもう片方にも入れる必要がある。この移植を、元PRとの対応が
追える形で作る。

リポジトリごとにどのブランチが並走しているかは `~/.claude/local-context.md` を見る。
**この skill には値を書かない**（dotfilesは public）。

## 引数

```
/backport-pr example-org/example-repo#628 main
/backport-pr https://github.com/example-org/example-repo/pull/479 main
```

- 第1引数: 元PR（URL または `owner/repo#番号`）
- 第2引数: 移植先のベースブランチ

**移植先を推測しない。** 第2引数が無ければ、元PRのbaseと `git branch -r` の一覧を出して
どこへ持っていくか確認を取る。リポジトリごとに正解が違い、間違えると作り直しになる。

## 手順

### 1. 元PRの情報を取る

```bash
gh pr view <元PR> --json number,title,body,baseRefName,headRefName,state,mergedAt,mergeCommit,commits,url
```

見るのは次の4つ。

| 項目 | 何に使うか |
| --- | --- |
| `baseRefName` | 移植元。移植先と同じなら誤りなので止める |
| `state` / `mergedAt` | マージ済みかどうかで、持っていくコミットの取り方が変わる |
| `mergeCommit` | squash mergeされていれば、この1コミットが変更の全体 |
| `commits` | 未マージなら、この一覧を順に持っていく |

### 2. 移植先ブランチの実在を確認する

```bash
git fetch origin
git rev-parse --verify "origin/<移植先>"
```

存在しなければ、ブランチ名の誤りとして止める。勝手に作らない。

### 3. 移植用ブランチを切る

移植先を起点にして、元のブランチ名から移植先が分かる名前にする。

```bash
git wt "<元のブランチ名>-<移植先>" "origin/<移植先>"
```

`git wt <branch> <start-point>` は start-point からworktreeを作る。
`git wt` が無い環境では `git worktree add .wt/<branch> -b <branch> origin/<移植先>` で代替し、
`~/scripts/worktree-init.sh` を明示的に叩く。

例: 元が `fix/tokyo-timezone` で移植先が `main` なら `fix/tokyo-timezone-main`。

### 4. 変更を持っていく

**マージ済み（squash merge）の場合** — mergeCommit 1つを cherry-pick する。

```bash
git cherry-pick <mergeCommitのoid>
```

**未マージ、またはマージコミットが複数コミットを保っている場合** — 元PRのコミットを古い順に cherry-pick する。

```bash
git cherry-pick <oldest>^..<newest>
```

**コンフリクトしたら止める。** 自動解決しない。両ブランチが分岐しているということは、
移植先では前提が違う可能性がある。コンフリクトの中身を出して、どう解決するかを確認する。

```bash
git cherry-pick --abort   # いったん戻す場合
```

cherry-pick が成立しないほど分岐している場合（ファイル構成が違うなど）は、
cherry-pickをやめて**同じ意図の変更を移植先の構造に合わせて書き直す**。
その場合はPR本文にその旨を明記する。移植と書いてあるのに差分が違うと、レビュアーが混乱する。

### 5. push する

```bash
git push -u origin "<移植用ブランチ>"
```

### 6. PRを作成する

タイトルは**元PRのタイトルに移植先を添える**。並んだときにどちらがどちらか分かるようにするため。

```
fix: 存在しないカテゴリの指定を500ではなく400で返す (main向け)
fix(reference): 日時の表示を Asia/Tokyo 固定にする（#11222 の取り込み / main向け）
```

本文は元PRの本文を土台にして、先頭に移植であることを書く。

```markdown
<元PRのURL> の <移植先> 向け移植です。

内容は元PRと同じ〔／ 移植にあたり ○○ を移植先の構造に合わせて変えています〕。

---

（以下、元PRの本文）
```

```bash
gh pr create --base "<移植先>" --title "<title>" --body "<body>"
```

`--base` は必ず明示する。省略するとデフォルトブランチに向く。

本文の書き方の詳細は `.config/claude/skills/wt-pr/references/pr-body.md`、
コミットを積み直す場合の分割基準は `.config/claude/skills/wt-pr/references/commit-split.md` を見る。

### 7. 報告する

- 作成したPRのURLとベースブランチ
- 元PRとの差分の有無（そのまま cherry-pick / 書き直しあり）
- コンフリクトを解決した場合はその箇所

元PR側にも移植先PRのリンクをコメントで残すと、あとから片側だけ見た人が
もう片方の存在に気づける。**ただしコメント投稿は外部への書き込みなので、
やる前に確認を取る。**

## よくある取り違え

**移植元と移植先が逆** — どちらからどちらへ流すかはリポジトリの運用で決まる。
元PRの `baseRefName` を見て、それが移植先と同じなら誤り。

**まだマージされていない元PRを移植する** — 元PRがレビューで変わると2本が食い違う。
未マージのまま移植する場合は、元PRの変更を移植先にも反映する必要があることを報告に書く。

**移植先で既に同じ修正が入っている** — cherry-pick が空になる（`nothing to commit`）。
その場合は移植不要として、PRを作らずに報告する。
