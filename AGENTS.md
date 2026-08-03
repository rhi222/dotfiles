# AGENTS.md

## リポジトリ概要

各種開発ツールやアプリケーションの設定ファイルを含む個人用dotfilesリポジトリです。シンボリックリンクを使用して、異なるシステム間で設定ファイルを管理しています。

## セットアップとインストール

### メインセットアップスクリプト

`./dotfilesLink.sh` を実行して、すべての設定ファイルのシンボリックリンクを作成：

- Git設定 (`.gitconfig`, `.config/git/`)
- Neovim設定 (`.config/nvim/`)
- Fish shell設定 (`.config/fish/`)
- ターミナルマルチプレクサ (`.config/tmux/`)
- 開発ツール (mise, lazygit, gitui, etc.)
- Claude Code設定 (`.config/claude/`)

### aptパッケージ管理

`scripts/apt-packages.txt` にWSL2環境で必要なaptパッケージを管理している。新しいaptパッケージが必要になった場合はこのファイルに追加する（`#`で始まる行はコメントとして無視される）。

一括インストールは `bash scripts/apt-setup.sh` を使う。内部で `apt update` を実行したうえでコメント/空行を除外して `apt install -y` する。

### Claude Code skill管理

外部 agent skill は `gh skill` (GitHub CLI v2.90.0+) で管理。宣言リストは `scripts/claude-skills.txt`。デフォルトで Claude Code (`~/.claude/skills/`) と Codex (`~/.codex/skills/`) の両方にインストールする（`SKILL_AGENTS` 環境変数で対象agentを変更可能）。

| やりたいこと         | コマンド                                                                                                           |
| -------------------- | ------------------------------------------------------------------------------------------------------------------ |
| skill 追加           | `bash scripts/skill-add.sh <owner/repo> <skill>`                                                                   |
| index 未登録リポ追加 | `claude-skills.txt` に `local: <git-url> <sub-path> <skill-name>` を手書き → `bash scripts/setup-claude-skills.sh` |
| 新環境 bootstrap     | `env STRICT=1 bash scripts/setup-claude-skills.sh`                                                                 |
| 更新                 | `daily-update.sh` が自動実行                                                                                       |
| 削除                 | `claude-skills.txt` の行削除 + `rm -rf ~/.claude/skills/<name> ~/.codex/skills/<name>`                             |

詳細は `scripts/setup-claude-skills.sh` と `scripts/skill-add.sh` 冒頭コメントを参照。

### gh CLI拡張管理

`gh` の拡張は宣言リスト `scripts/gh-extensions.txt` で管理する。skill が拡張コマンドを前提にしている場合（例: `gh-stack` skill → `gh stack`）、skill だけ入れても新環境で動かないため、拡張側もここに並べて宣言する。

| やりたいこと     | コマンド                                                                         |
| ---------------- | -------------------------------------------------------------------------------- |
| 拡張追加         | `gh-extensions.txt` に `<owner>/<repo>[@<version>]` を追記 → 下の一括インストール |
| 一括インストール | `bash scripts/setup-gh-extensions.sh`（インストール済みはskip）                   |
| 新環境 bootstrap | `env STRICT=1 bash scripts/setup-gh-extensions.sh`                               |
| 更新             | `daily-update.sh` が `gh extension upgrade --all` を実行                          |
| 削除             | `gh-extensions.txt` の行削除 + `gh extension remove <name>`                       |

`@<version>` を付けるとそのリリースタグに `--pin` する。動作確認は `bash scripts/test-gh-extensions.sh`。

### Windowsトースト通知（WSL2専用）

Claude Code のフックと cron から、Windows側の `BurntToast` (PowerShell) でトースト通知を出す。エントリポイントは `.config/claude/hooks/notify-windows.sh`（`Stop` / `Notification` フックに登録）と `scripts/nippo-cron.sh`。

共通処理は `scripts/lib/` に分けている。

| ファイル                      | 役割                                          |
| ----------------------------- | --------------------------------------------- |
| `lib/notify-windows-toast.sh` | `send_windows_toast` — BurntToast 呼び出し     |
| `lib/stop-notification.sh`    | Stop通知のタイトル・本文の組み立て             |
| `lib/notify-cooldown.sh`      | `notify_cooldown_should_send` — 同一通知の抑止 |

依存:

- WSL2 + `wslu` (`apt-packages.txt` 経由)
- Windows側 PowerShell の `BurntToast` モジュール（`Install-Module BurntToast`）
- `jq`（同上）

#### 完了通知（Stopフック）

タイトルに作業中のリポジトリ名とブランチ、本文にトランスクリプトから抽出した最後のアシスタント発言（サブエージェント分は除外、1行120文字に整形）を出す。

```
✅ dotfiles (main)
テストを追加してlintも通りました。コミット済みです。
```

本文の長さは `STOP_NOTIFICATION_SUMMARY_MAX` で変えられる。トランスクリプトが読めない場合は `タスクが完了しました` にフォールバックする。

#### 日報リマインド通知

平日の業務時間中に日報の状態をチェックして通知する。`nippo-check.sh` は呼び出し元コンテキストを第1引数で受け取り、報告する内容を変える。

| チェック           | stop | cron |
| ------------------ | ---- | ---- |
| 📝 日報未作成      | ✓    | ✓    |
| 🟢 タイマー未終了  | ✓    | ✓    |
| 📊 finalize忘れ    | ✓    | ✓    |
| ⏰ 90分以上未更新  | −    | ✓    |
| 📋 未完了タスクN件 | −    | ✓    |

`stop` は応答が終わるたびに発火するので、一日中真になり続ける下2つは cron 専用にしている。加えて Stop フック側で二段のゲートを掛ける。

1. **実行ゲート** — チェック自体を10分に1回まで。日報は `/mnt/c` (9p) 上にあり1ファイル操作あたり数秒かかるため
2. **通知クールダウン** — 同じ内容の通知は60分に1回まで。内容が変われば窓の途中でも通知する

状態は `~/.cache/claude-nippo-notify/{last-run,last-notify}` に持つ。通知が来なくなったと思ったらこの2ファイルを消せばリセットされる。

セットアップ:

```fish
touch ~/.config/nippo-notify-enabled
crontab -e
# 以下を追加
# 0 9,11,13,15,17,19 * * 1-5 $HOME/scripts/nippo-cron.sh >> $HOME/.nippo-cron.log 2>&1
```

無効化は `rm ~/.config/nippo-notify-enabled`。動作確認は `scripts/test-nippo-check.sh` / `scripts/test-notify-cooldown.sh` / `scripts/test-stop-notification.sh`。

### 日報ドラフト自動仕上げ（WSL2専用）

平日18:30に `scripts/nippo-draft-cron.sh` が `nippo-finalize` スキルをヘッドレス実行し、日報ドラフトを自動で仕上げる。人間は生成結果をレビューするだけにする。

日報には当日のGitHub活動（作成PR・マージPR・自PRのレビュー状況・実施したレビュー）を `gh` で自動収集して追記する。`gh auth status` が通らない環境では該当フェーズをスキップして続行する。

セットアップ:

```fish
# まず手動でヘッドレス実行を1回試す（生成結果の妥当性を確認する）
touch ~/.config/nippo-draft-enabled
env NIPPO_DRAFT_FORCE=1 bash scripts/nippo-draft-cron.sh

# 問題なければcronに登録する
crontab -e
# 以下を追加
# 30 18 * * 1-5 $HOME/scripts/nippo-draft-cron.sh >> $HOME/.nippo-draft-cron.log 2>&1
```

無効化は `rm ~/.config/nippo-draft-enabled`。動作確認は `bash scripts/test-nippo-draft-cron.sh`。

### esa週次レポート自動生成（WSL2専用）

毎週金曜16:00に `scripts/esa-weekly-cron.sh` が `esa-weekly-report` スキルをヘッドレス実行し、部長会向けドラフトを `~/Obsidian/05_Organization/Buchokai/` に出力する。人間は生成結果をレビューするだけにする。

セットアップ:

```fish
# まず手動でヘッドレス実行を1回試す（esa APIアクセスと生成結果を確認する）
touch ~/.config/esa-weekly-enabled
bash scripts/esa-weekly-cron.sh

# 問題なければcronに登録する
crontab -e
# 以下を追加
# 0 16 * * 5 $HOME/scripts/esa-weekly-cron.sh >> $HOME/.esa-weekly-cron.log 2>&1
```

無効化は `rm ~/.config/esa-weekly-enabled`。動作確認は `bash scripts/test-esa-weekly-cron.sh`。

## 設定アーキテクチャ

### Neovim設定構造

Neovim設定は `.config/nvim/lua/my/` 下でモジュラー構造に従っています：

- **名前空間戦略**: プラグイン名との競合を避けるため `my/` プレフィックスを使用
- **プラグイン管理**: lazy.nvimを使用してプラグイン管理
- **モジュラー設計**: 設定、プラグイン、コマンドを個別のモジュールに分離
- **キーバインド哲学**: Space、Ctrl、特殊キーを使用した覚えやすいプレフィックスベースのキーマップを優先

### Fish Shell設定

モジュラー構造でカテゴリ別に整理：

```
.config/fish/
├── config.fish                 # メイン設定
└── my/conf.d/
    ├── 01-mise.fish            # mise（ランタイム管理）
    ├── 02-history.fish         # 履歴設定
    ├── 03-environment.fish     # 環境変数
    ├── 04-paths.fish           # PATH設定
    ├── 05-tide-settings.fish   # tideプロンプト設定
    ├── 06-aliases.fish         # エイリアス
    ├── 07-abbr.fish            # 略語
    ├── 08-prompt-override.fish # カスタムプロンプト（tide拡張）
    ├── 09-git-wt.fish          # Git worktree
    ├── 10-fzf.fish             # fzf設定
    └── 11-yazi.fish            # yazi連携（cdキーバインド等）
```

- **エイリアス（06-aliases.fish）**: Gitショートカット、開発ツールエイリアス (tmux, nvim, etc.)
- **略語（07-abbr.fish）**: よく使用するコマンドのスマート展開 (git, docker compose)
- **ツール統合**: ランタイム管理用mise、ディレクトリナビゲーション用zoxide
- **Docker Compose ヘルパー**: プロジェクトディレクトリ内のcomposeファイルの自動発見

### 開発環境

- **ランタイム管理**: Node.js、Python、Go等のランタイム管理にmise（旧rtx）を使用
- **Git設定**: 従来のコミット形式を使用するカスタムコミットメッセージテンプレート
- **ターミナル設定**: tideプロンプトテーマで256色サポート設定

## 主要ツールとコマンド

### Gitワークフロー

- コミットメッセージは従来のコミット形式に従う (feat, fix, docs, etc.)
- `.config/git/commit-conventions.txt` でテンプレート利用可能
- 最近のブランチ用 `gbr` 略語でブランチ管理

### worktree初期化のリポジトリ別カスタム

`git wt` でworktreeを作成すると `scripts/worktree-init.sh` が走り、共通処理（gitignore対象の
`.env*` コピー・lockファイル判定による依存インストール）を行う。共通処理の後に、リポジトリ固有の
追加初期化を差し込める。

- 置き場所: `scripts/worktree-init.d/<host>/<owner>/<repo>.sh`
  （例 `scripts/worktree-init.d/github.com/rhi222/dotfiles.sh`）
- キーは `git remote get-url origin` の正規化名（`git@`/`https`/`ssh` いずれの形式でも同一キーに解決）
- 固有スクリプトは `cwd=worktreeパス`・第1引数にworktreeパスが渡って実行される
- 固有スクリプトが失敗しても警告が出るだけで worktree 作成フローは継続する（`worktree-init.sh` は exit 0）
- 該当スクリプトが無いリポジトリ、または origin未設定のリポジトリでは共通処理のみ実行される

### Docker開発

- `find_docker_compose` 関数でcomposeファイルを自動検出
- 略語: `dc` (docker compose), `dcl` (logs), `dcu` (up), `dcd` (down)
- 複数のcomposeファイルの場所と命名パターンをサポート

### Neovimプラグイン管理

- `lazy-lock.json` のロックファイルでlazy.nvimを使用したプラグイン管理
- `lua/my/plugins/` で機能別にプラグインを整理
- LSPサーバー管理用Mason
- AI支援用Copilot統合

## ファイル構造パターン

### 設定の整理

- ルートのシステム全体設定 (`.gitconfig`)
- XDG Base Directory Specificationに従った `.config/` のユーザー設定
- 各ツールディレクトリの言語固有設定
- **Fish設定**: 機能別にモジュール分割（エイリアス、略語、環境変数など）

### Neovim Luaモジュール

- `my/settings/`: コアNeovim設定とautocmds
- `my/plugins/`: 個別プラグイン設定
- `my/commands/`: カスタムユーザーコマンド
- requireベースの読み込みパターンに従う

## 重要な注意事項

- 一部の設定ファイルで日本語コメントを使用
- Windows Docker統合によるWSL2環境サポート
- 企業環境用Zscaler証明書設定
- Fish shellでtideプロンプトテーマ（コピー＆ペーストの利便性のため右プロンプトは無効）
