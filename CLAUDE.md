# CLAUDE.md

このファイルは、このリポジトリでコードを操作する際のClaude Code (claude.ai/code) への指針を提供します。

## リポジトリ概要

各種開発ツールやアプリケーションの設定ファイルを含む個人用dotfilesリポジトリです。シンボリックリンクを使用して、異なるシステム間で設定ファイルを管理しています。

## セットアップとインストール

### メインセットアップスクリプト

`./dotfilesLink.sh` を実行して、すべての設定ファイルのシンボリックリンクを作成：

- Git設定 (`.gitconfig`, `.config/git/`)
- Neovim設定 (`.config/nvim/`)
- Fish shell設定 (`.config/fish/`)
- ターミナルマルチプレクサ (`.tmux.conf`)
- 開発ツール (mise, lazygit, gitui, etc.)
- Claude Code設定 (`.config/claude/`)

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
    ├── 04-paths.fish          # PATH設定
    ├── 05-colors.fish         # 色設定
    ├── 06-prompt.fish         # プロンプト設定
    ├── 07-aliases.fish        # エイリアス
    └── 08-abbr.fish           # 略語
```

- **エイリアス（07-aliases.fish）**: Gitショートカット、開発ツールエイリアス (tmux, nvim, etc.)
- **略語（08-abbr.fish）**: よく使用するコマンドのスマート展開 (git, docker compose)
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

- ルートのシステム全体設定 (`.gitconfig`, `.tmux.conf`)
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
