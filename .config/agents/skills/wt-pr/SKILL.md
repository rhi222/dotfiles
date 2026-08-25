---
name: wt-pr
description: git worktreeを切って実装し、コミット分割・push・PR作成までを一気通貫で行う。「worktreeで作業して」「worktree切ってPRまで作って」「branch切ってからcommit, push, PR作成して」「PRつくるまでやっていいよ」や、Jira/LinearのチケットURL・番号を渡して実装を頼まれた文脈で使用。実装をブランチに載せてPRにするまでを1回で流したいときは、worktreeという語が出ていなくてもこのスキルを使う。既にPRがあり別ブランチへ同じ変更を持っていく場合は backport-pr を使う。
---

# worktreeで実装してPRを出すまで

入力形式: `<やること、またはJira/LinearのチケットURL・番号>`

worktreeを切る → 実装する → コミットを分割して積む → push → PR作成、までを1本で流す。

**worktreeを使う理由は、メインの作業ツリーを止めないため。** 複数の案件が並行し、
レビュー待ちのブランチと新しい実装が同時に走るので、`git switch` で行き来すると
未コミットの変更を抱えたまま切り替える事故が起きる。worktreeなら物理的に別ディレクトリになる。

## このスキルがやらないこと

- **既存PRの別ブランチへの移植** — `backport-pr` の担当
- **stacked PR の管理** — `gh-stack`（gh CLI拡張）の担当
- **worktreeの掃除** — `bash scripts/worktree-cleanup.sh`（既定はdry-run）

## 前提

worktree管理は `git wt`（github.com/k1LoW/git-wt）に一本化している。
`git wt <branch>` で作成すると `wt.hook` 経由で `~/scripts/worktree-init.sh` が走り、
gitignore対象の `.env*` のコピーと依存インストール（pnpm/npm/yarn をlockファイルで判定）
まで済んだ状態で、新しいworktreeへ自動cdする。保存先はリポジトリ内の `.wt/`。

Claude Code の `EnterWorktree` を使える環境では、PostToolUse hook から同じ初期化が走る。
Codexを含むそれ以外の環境では `git wt` を使う。どちらの経路でも初期化は冪等なので、
迷ったら `~/scripts/worktree-init.sh` を叩き直してよい。

## 手順

### 1. 作業対象とベースブランチを確定する

チケットURL・番号が渡されていれば、まず内容を引いて何をするかを掴む。

**ベースブランチは推測せず確定させる。** デフォルトブランチとは限らない。
案件別の長命ブランチが正で、デフォルトブランチへ出すと差し戻しになるリポジトリがある。
リポジトリごとの対応は `~/.claude/local-context.md` を見る。
**この skill には値を書かない**（dotfilesは public）。

```bash
git remote show origin | grep 'HEAD branch' | awk '{print $NF}'   # デフォルト
git branch -r | grep -E 'develop|main|master' | head              # 候補の実在確認
```

判断の順序は次のとおり。

1. ユーザーがベースブランチを明示している → それに従う
2. `~/.claude/local-context.md` にそのリポジトリの対応がある → その値を候補として**確認を取る**
3. どちらでもない → デフォルトブランチを使う（確認は不要）

### 2. ブランチ名を決める

`<type>/<チケット番号>-<英小文字のslug>` を基本形にする。

| 例 | 由来 |
| --- | --- |
| `feature/PROJ-123-add-retry` | Jira番号あり・機能追加 |
| `fix/issue-266-max-id-numeric-compare` | GitHub issue番号あり・修正 |
| `chore/PROJ-125-unify-actions-refs` | 雑務 |

`type` はコミットのprefixと同じ語彙（feat / fix / refactor / chore / docs / test / ci）から選ぶ。
チケット番号が無ければ省略してよいが、slugだけは必ず内容が分かる語にする。

### 3. worktreeを作る

```bash
git wt <branch>
```

ブランチが既にあれば切り替え、無ければ作成される。実行後は新しいworktreeにいる。
`pwd` で移動先を確認してから実装に入る。

初期化hookが動かなかった場合（herdr経由など）は明示的に叩く。

```bash
~/scripts/worktree-init.sh
```

### 4. 実装する

会話の文脈・チケットの内容に沿って実装する。ここはこのスキルの管轄外なので、
プロジェクトの `AGENTS.md` / `CLAUDE.md` など、そのagent向けの指示とテスト方針に従う。

### 5. コミットを分割して積む

**1コミット＝1つの論理的変更**にする。分割の判断基準とprefixの選び方は
`references/commit-split.md` に置いてあるので、複数の関心事が混ざっていると感じたら読む。

ステージは意図した差分だけに絞る。

```bash
git add -p              # ハンク単位
git add <path>          # ファイル単位
git diff --staged       # 単一の意図に閉じているか確認してからコミット
```

コミットメッセージにagent生成の署名や `Co-Authored-By` を自動追加しない。

### 6. push する

```bash
git push -u origin <branch>
```

**ここが不可逆の境目になる。** ユーザーの依頼にPR作成までの認可が含まれているか確認する。

| 依頼の文言 | 扱い |
| --- | --- |
| 「PRつくるまでやっていいよ」「commit, push, PR作成して」 | 認可あり。そのまま進む |
| 「実装して」「直して」だけ | 認可なし。**pushの手前で止めて、差分の要約とブランチ名を出して確認を取る** |

### 7. PRを作成する

タイトルと本文の作り方は `references/pr-body.md` に従う。

```bash
gh pr create --base <ベースブランチ> --title "<title>" --body "<body>"
```

**ベースブランチは `--base` で必ず明示する。** 省略するとデフォルトブランチに向き、
案件別ブランチ運用のリポジトリで作り直しになる。

### 8. 報告する

次の3点を出す。

- PRのURLとベースブランチ
- 積んだコミットの一覧（`git log --oneline <base>..HEAD`）
- 今いるworktreeのパス

worktreeはPRがマージされるまで残す。掃除は `bash scripts/worktree-cleanup.sh`（既定dry-run、
実削除は `--execute`）で、マージ済み・未lockのものだけが候補になる。

## つまずいたときの扱い

**pre-commitやCIが落ちた** — 自動で握り潰さない。落ちた内容を出して、修正方針をユーザーに判断してもらう。
lintのような機械的な指摘は直してよいが、テストの失敗は実装の問題を示している可能性がある。

**`git wt` が無い環境** — `git worktree add .wt/<branch> -b <branch>` で代替し、
そのあと `~/scripts/worktree-init.sh <path>` を明示的に叩く。

**worktreeが既に大量にある** — 作る前に `git wt` で一覧を見る。同じチケットのworktreeが
既にあれば、新規作成ではなくそこへ切り替える。
