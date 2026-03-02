# git-wt vs gwq 比較レポート

## 概要

どちらもGoで書かれたgit worktree管理ツールで、miseの`.default-go-packages`経由でインストールされている。

| 項目         | git-wt                               | gwq                                                   |
| ------------ | ------------------------------------ | ----------------------------------------------------- |
| 作者         | k1LoW                                | d-kuro                                                |
| GitHub       | github.com/k1LoW/git-wt              | github.com/d-kuro/gwq                                 |
| コマンド体系 | `git wt` (gitサブコマンド)           | `gwq` (独立コマンド)                                  |
| 設計思想     | 単一リポジトリのworktree操作を簡素化 | 複数リポジトリのworktreeをグローバル管理（ghqライク） |

---

## git-wt の使い方

### 基本コマンド

```bash
git wt                     # worktree一覧表示
git wt <branch>            # worktree作成 or 切り替え（自動cd）
git wt <branch> <start>    # start-pointからworktree作成
git wt -d <branch>         # 安全な削除（マージ済みチェック）
git wt -D <branch>         # 強制削除
git wt --json              # JSON形式で一覧出力
```

### このリポジトリでの設定

- **シェル統合**: `09-git-wt.fish` で `git wt --init fish | source` を実行
  - `git wt <branch>` 実行時に自動的にディレクトリ移動
- **fzf連携**: 3つのfish関数で構成
  - `wt`: インタラクティブにworktreeを選択・切り替え（コミットログのプレビュー付き）
  - `wtd`: fzfでworktreeを選択して削除
  - `__wt_select`: `wt`/`wtd`共通のfzfヘルパー（worktreeをフォーマット＆プレビュー付き選択）
- **worktree保存先**: デフォルトの `.wt/`（リポジトリ内）
- **カスタムプロンプト**: `08-custom-prompt.fish` でworktree判定アイコンを表示
  - `🏠` メインリポジトリ、`🌿` worktree内、`📂` Git管理外

### git config設定（`.gitconfig` `[wt]`セクション）

```ini
[wt]
    relative = true       # サブディレクトリの相対パスを付与
    nocd = create         # worktree作成時は自動cdしない
    copy = CLAUDE.md      # worktree作成時にCLAUDE.mdをコピー
    hook = "tmux neww -c \"$PWD\" -n \"$(basename ...)\" \\; splitw -h -c \"$PWD\" 'claude'"
```

- `relative`: 現在のサブディレクトリパスをworktreeにも反映
- `nocd = create`: 作成時のみ自動cdを無効化（切り替え時は有効）
- `copy = CLAUDE.md`: worktreeにCLAUDE.mdを自動コピー（AI開発用）
- `hook`: worktree作成後にtmuxで新ウィンドウ＋Claude CLIを自動起動

### 主な設定オプション（git config経由）

- `wt.basedir`: worktreeの作成先ディレクトリ
- `wt.copyignored/copyuntracked/copymodified`: ファイルコピー制御
- `wt.hook`: worktree作成後に実行するコマンド
- `wt.nocd`: 自動cd制御
- `wt.relative`: サブディレクトリパスの付与

---

## gwq の使い方

### 基本コマンド

```bash
gwq add <branch>           # worktree作成
gwq add -b <new-branch>    # 新ブランチでworktree作成
gwq add -i                 # インタラクティブ選択
gwq list                   # worktree一覧
gwq list -g                # 全リポジトリのworktreeを横断表示
gwq get <branch>           # worktreeのパスを取得
gwq cd <branch>            # worktreeに移動（新シェル起動）
gwq exec <cmd>             # worktree内でコマンド実行
gwq remove <branch>        # worktree削除
gwq status                 # ステータス表示（差分・変更ファイル）
gwq tmux                   # tmuxセッション管理
gwq prune                  # 不要なworktree情報のクリーンアップ
```

### このリポジトリでの設定

- **略語**: `07-abbr.fish` で `gw` → `cd (gwq get)` を定義
- **設定ファイル**: `.config/gwq/config.toml`
  - worktree保存先: `~/git-worktrees`
  - 命名テンプレート: `Host/Owner/Repository/Branch`（`/` → `-`, `:` → `-` にサニタイズ）
  - UI: アイコン有効、ホームディレクトリをチルダ表示
  - finder: プレビュー有効
  - Claude Code連携が設定済み（並列タスク管理）
- **レジストリ**: `.config/gwq/registry.json` でworktreeを追跡（現在は空）

### Claude Code連携の設定

```toml
[claude]
config_dir = '~/.config/gwq/claude'
executable = 'claude'
max_development_tasks = 2      # 同時開発タスク数
max_parallel = 3               # 並列実行数

[claude.execution]
auto_cleanup = true            # 完了タスクの自動クリーンアップ

[claude.queue]
queue_dir = '~/.config/gwq/claude/queue'

[claude.worktree]
auto_create_worktree = true    # worktree自動作成
require_existing_worktree = false
validate_branch_exists = true  # ブランチ存在チェック
```

---

## 比較: メリット・デメリット

### git-wt

**メリット**

- gitサブコマンドとして動作し、`git wt` で呼べるため直感的
- シェル統合による自動cd（`git wt <branch>` で即座に移動）
- シンプルなAPI。覚えることが少ない
- git configで設定できる（追加の設定ファイル不要）
- hook/deletehookでworktree作成・削除時の自動処理
- fzfとの組み合わせが容易（`wt`/`wtd`関数で実現済み）
- `copy`オプションでCLAUDE.md等を自動コピー可能
- hookでtmux+Claude CLI自動起動が可能

**デメリット**

- 単一リポジトリスコープ。リポジトリ横断の管理ができない
- デフォルトのworktree保存先が `.wt/`（リポジトリ内）で散らかりやすい
- bare repositoryに非対応
- ステータス監視やwatch機能がない

### gwq

**メリット**

- 全リポジトリのworktreeをグローバルに一元管理（`gwq list -g`）
- `~/git-worktrees` に統一的なディレクトリ構造（`Host/Owner/Repo/Branch`）
- ghqライクな設計で、ghqと併用しやすい
- Claude Code連携が組み込み。AIエージェントの並列開発ワークフローをサポート
- `gwq status` でworktree全体のgit変更状況を横断確認
- tmux統合で長時間プロセス管理
- レジストリによるworktree追跡
- TOML設定ファイルで柔軟な設定（グローバル + プロジェクトローカル）

**デメリット**

- コマンド数が多く、学習コストがやや高い
- 独立コマンドのため `git` の延長線上で使えない
- シェル統合による自動cdがない（`cd (gwq get)` で代替）
- 比較的新しいツールでエコシステムが小さい

---

## 使い分けの指針

| ユースケース                               | 推奨ツール |
| ------------------------------------------ | ---------- |
| 単一リポジトリ内でブランチを素早く切り替え | **git-wt** |
| 複数リポジトリのworktreeを横断管理         | **gwq**    |
| Claude Codeとの並列開発ワークフロー        | **gwq**    |
| git操作の延長で手軽に使いたい              | **git-wt** |
| worktreeのステータスを一覧確認             | **gwq**    |
| ghqと統一的なワークフロー                  | **gwq**    |
| 最小限のセットアップで使いたい             | **git-wt** |
| worktree作成時にtmux+claude自動起動        | **git-wt** |

### 現在のリポジトリの状態

- **git-wt**: Fish統合済み（コミット済み）。`wt`/`wtd`関数でfzf連携。git configにhook設定（`.gitconfig`は未コミット変更あり）
- **gwq**: 設定ファイル済み（コミット済み）。`gw`略語で利用。Claude連携設定あり
- **カスタムプロンプト**: worktree判定アイコン表示が実装済み（コミット済み）
- 両方とも `.default-go-packages` でインストール済み

両ツールは競合せず、併用可能。git-wtは「今いるリポジトリのworktreeを手早く操作」、gwqは「プロジェクト横断のworktree管理とAI開発ワークフロー」という棲み分けができる。
