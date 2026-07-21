# git worktree運用ガイド

worktree管理は **git-wt**（github.com/k1LoW/git-wt）に一本化している。
gwq は2026-07に廃止した（設定はあったが実運用されていなかったため）。

## 基本コマンド

```bash
git wt                     # worktree一覧表示
git wt <branch>            # worktree作成 or 切り替え（切り替え時は自動cd）
git wt <branch> <start>    # start-pointからworktree作成
git wt -d <branch>         # 安全な削除（マージ済みチェック）
git wt -D <branch>         # 強制削除
git wt --json              # JSON形式で一覧出力
```

## このリポジトリでの設定

- **シェル統合**: `09-git-wt.fish` で `git wt --init fish` の出力をキャッシュしてsource
- **fzf連携**: 3つのfish関数で構成
  - `wt`: インタラクティブにworktreeを選択・切り替え（コミットログのプレビュー付き）
  - `wtd`: fzfでworktreeを選択して削除
  - `__wt_select`: `wt`/`wtd`共通のfzfヘルパー
- **worktree保存先**: デフォルトの `.wt/`（リポジトリ内）
- **カスタムプロンプト**: `08-prompt-override.fish` でworktree判定アイコンを表示
  - `🏠` メインリポジトリ、`🌿` worktree内、`📂` Git管理外

### git config設定（`.gitconfig` `[wt]`セクション）

```ini
[wt]
    relative = true       # サブディレクトリの相対パスを付与
    nocd = create         # worktree作成時は自動cdしない
    copy = CLAUDE.md      # worktree作成時にCLAUDE.mdをコピー
    hook = "bash \"$HOME/scripts/worktree-init.sh\""  # 作成後の初期化
```

tmux+claude の自動起動hookは2026-07に廃止し、hookは初期化処理専用にした
（herdr移行によりtmux前提が崩れたため。エージェント起動は手動または herdr 側で行う）。

## worktree-init.sh（作成後の初期化）

どの経路（git-wt / Claude Code / herdr / 手動 `git worktree add`）で作った
worktreeでも、以下で初期化できる（冪等）:

```fish
~/scripts/worktree-init.sh [--dry-run] [worktreeパス]  # パス省略時はカレント
```

処理内容:

- メインworktreeから gitignore対象の `.env*` を相対パス維持でコピー
  - 既存ファイルは上書きしない（冪等）
  - `node_modules` / `.wt` 配下は対象外
  - trackedファイル（`.env.example` 等）は対象外
- lockファイルを判定して依存をインストール
  - `pnpm-lock.yaml` → `pnpm install`
  - `package-lock.json` → `npm ci`
  - `yarn.lock` → `yarn install`
  - 該当なし → スキップ

`git wt <branch>` での作成時は `wt.hook` 経由で自動実行される。
テストは `bash scripts/test-worktree-init.sh`。
