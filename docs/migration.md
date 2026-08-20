# PC 移行（リポジトリ群の運び方）

`/data/git-repos` 配下のリポジトリ群と、その中の**ローカル専用の作業状態**
（未pushブランチ・stash・worktree・gitignore 下の `.env` 等）を新しい端末へ運ぶ手順。

環境そのものの立ち上げ（dotfiles・機密ファイル・cron・Claude のメモリと履歴）は
[bootstrap.md](bootstrap.md) の担当で、この文書はその前段にあたる。
移行対象リポジトリの**具体名はここに書かない**（社内名を含むため）。移行のたびに
下の判定コマンドで洗い出す。

## 方針: 再clone を基本とし、ローカル専用の状態が残るリポジトリだけ tar で運ぶ

ghq root の丸ごとコピーはやらない。2026-08 の移行時の実測で全体は 54GB あったが、
大半は node_modules 等の生成物で、tar が必要なリポジトリだけを生成物除外で固めると
**合計 2GB 弱**に収まった。

ただし**パスは新旧の端末で揃える**。次の4つが絶対パスに依存しており、
パスが変わると個別に壊れる。

1. **ghq root**（`.gitconfig` の `ghq.root = /data/git-repos`）
2. **git worktree の登録**（`.git/worktrees` は絶対パスを持つ。同一パスに展開すれば生きる）
3. **cross-repo skill の `repos.yml`**（エイリアス→絶対パスの対応表）
4. **Claude Code のメモリ**（`~/.claude/projects/` のディレクトリ名がプロジェクトの
   絶対パス由来。[bootstrap.md](bootstrap.md) の「Claude Code のメモリと履歴を運ぶ」参照）

ユーザー名（`$HOME` のパス）と WSL2 のマウント構成（`/data`、`/mnt/c`）も同じ理由で揃える。

## リポジトリを3グループに分ける

| グループ | 判定 | やること |
| --- | --- | --- |
| ① tar で運ぶ | 未pushブランチ・stash・worktree・dirty が残る | 生成物を除外して tar。**`.git` ごと入るので新PCでは clone せず展開するだけ** |
| ② ファイルだけ収集 | 差分が gitignore 下のローカル設定（`.env` / `.claude/settings.local.json` / superpowers 作業文書）のみ | 対象ファイルを相対パス付きで1つの tar に収集。新PCで再clone した後に展開 |
| ③ 再clone のみ | ローカル専用の状態が無い | `ghq get` で取り直す。何も運ばない |

**push できるものは先に push して①を減らす**のが最初の一手。ahead のブランチ、
upstream の無い main、価値のある未追跡ファイルの commit がこれにあたる。

### 判定コマンド

```fish
# 未push・stash・dirty・worktree が残るリポジトリを洗い出す（①候補）
for r in (ghq list -p)
    set -l unpushed (git -C $r log --branches --not --remotes --oneline 2>/dev/null | count)
    set -l stash (git -C $r stash list 2>/dev/null | count)
    set -l dirty (git -C $r status --porcelain 2>/dev/null | count)
    set -l wt (git -C $r worktree list 2>/dev/null | tail -n +2 | count)
    if test $unpushed -gt 0 -o $stash -gt 0 -o $dirty -gt 0 -o $wt -gt 0
        echo "$r unpushed:$unpushed stash:$stash dirty:$dirty worktree:$wt"
    end
end

# remote を持たないリポジトリ（push できず、コピーしないと消える）と
# ghq 管理外の野良リポジトリも忘れずに見る
find ~ -maxdepth 2 -name .git -not -path "$HOME/.*/*"
```

## ① tar で運ぶ

```fish
# 旧PCで。生成物を除外して固める
tar czf ~/migrate/<repo>.tar.gz \
    --exclude=node_modules --exclude=.next --exclude=dist --exclude=.turbo \
    --exclude=coverage --exclude=.venv --exclude=cdk.out \
    -C /data/git-repos/<host>/<owner> <repo>

# 新PCで。clone せずに同一パスへ展開する（.git ごと復元される）
tar xzf <repo>.tar.gz -C /data/git-repos/<host>/<owner>
```

- **tar 前に `du -sh --exclude=...` でサイズを確認する。** 想定外に大きければ
  除外パターンの漏れ（別名のビルド出力・キャッシュ）を疑う
- **展開後は各リポジトリで生成物を作り直す**（`pnpm install` 等）。リポジトリ内に
  worktree（`.wt/` 等）を持つ場合はそちらも同様
- リポジトリ外に worktree がある場合は `git worktree list` で場所を確認し、
  持っていかないなら新PCで `git worktree prune` で登録を掃除する

## ② ファイルだけ収集する

再clone するリポジトリのうち、gitignore 下のローカル設定だけが差分のもの。
`.env` の実体は取得し直すコストが最も大きいので、ここの取りこぼしが移行の失敗になる。

```fish
# 旧PCで。/data/git-repos からの相対パスを保ったまま1つに固める
cd /data/git-repos
begin
    find . -maxdepth 4 \( -name '.env*' -not -name '*example*' -not -name '*sample*' \
        -not -name '*template*' -o -path '*/.claude/settings.local.json' \) \
        -not -path '*/node_modules/*'
    find . \( -path '*/docs/superpowers/*' -o -path '*/.superpowers/*' \) \
        -not -path '*/node_modules/*'
end | tar czf ~/migrate/repo-local-files.tar.gz -T -

# 新PCで。再clone を済ませてから展開する
tar xzf repo-local-files.tar.gz -C /data/git-repos
```

- `.claude/settings.local.json` はリポジトリ別の Claude Code 権限設定。消えると
  許可プロンプトが全部初期状態に戻る
- superpowers 作業文書（`docs/superpowers/` / `.superpowers/`）は gitignore 下にあり
  clone では戻らない。残さないと決めたリポジトリの分は find から除外する
- `.env` の探索は `-maxdepth 4` なので、それより深い階層に実体を置くリポジトリが
  あれば個別に足す

## 運ばないもの

- **生成物**（node_modules・ビルド出力・キャッシュ）— 新PCで作り直す
- **Docker の匿名ボリューム・build cache** — 同上。named volume に開発 DB 等を
  持っている場合だけ個別に判断する
- **remote を持たない使い捨てリポジトリ** — 残す価値があるなら移行前に push 先を作る。
  作らないと決めたものは消える前提で見送る
