# dotfiles

WSL2（Ubuntu）+ Windows で使っている個人用の設定ファイル群。シンボリックリンクで各ツールへ配る。

## 何が入っているか

| 領域 | 主なもの |
| --- | --- |
| シェル | fish（機能別に分割した `conf.d` と自作関数）、tide プロンプト |
| エディタ | Neovim（lazy.nvim + Mason。`lua/my/` 名前空間で分割） |
| 端末 | tmux、alacritty、herdr、yazi |
| Git | `.gitconfig`、コミットテンプレート、lazygit / gitui |
| AI コーディング | Claude Code（skill / hook / statusline）、Codex |
| 作業自動化 | 日報・週次レポート・タスク起票を cron から headless で回すスクリプト群 |

## セットアップ

```fish
ghq get rhi222/dotfiles
cd (ghq root)/github.com/rhi222/dotfiles

bash scripts/apt-setup.sh   # apt パッケージ
./dotfilesLink.sh           # リンク作成 + 雛形生成 + git hook 有効化
```

**`dotfilesLink.sh` だけでは完了しない。** gitignore しているファイル（認証情報や環境固有の値）が別途要る。通し手順は [AGENTS.md](AGENTS.md) を参照。

## 開発

```fish
bash scripts/lint.sh        # shellcheck + shfmt
bash scripts/run-tests.sh   # 全テスト
bash scripts/secret-scan.sh --tree
```

- シェルスクリプトは `scripts/` に置き、`scripts/test-<名前>.sh` でテストを書く。`run-tests.sh` が自動で拾う
- CI で動かせないテストは、テストファイルの先頭付近に `# ci-skip: <理由>` と書いて宣言する
- lint は git が追跡している（＋未追跡で ignore されていない）`*.sh` すべてを対象にする

## このリポジトリは public

社名・社内ホスト名・社内リポジトリ名・Jira プロジェクトキー・案件コード・顧客略号は入れない。
それらは gitignore 対象のファイルかリポジトリ外に置き、ここにはプレースホルダ入りの `.example` だけを置く。

検査は2層で、commit 前の pre-commit hook（社内語を含む実辞書）と、push / PR 時の GitHub Actions（汎用パターンのみ）で行う。詳しくは AGENTS.md の「社内固有情報を入れない運用」を参照。

## ドキュメント

- [AGENTS.md](AGENTS.md) — 設計判断とその理由。各機能の詳細はここに集約している（`CLAUDE.md` は同じファイルへの symlink）
- [docs/git-worktree-tool.md](docs/git-worktree-tool.md) — worktree 運用
- [docs/tmux-session-restore-strategy.md](docs/tmux-session-restore-strategy.md) — reboot 後のセッション復元
