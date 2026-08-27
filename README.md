# dotfiles

WSL2（Ubuntu）+ Windows で使っている個人用の設定ファイル群。シンボリックリンクで各ツールへ配る。

## 何が入っているか

| 領域            | 主なもの                                                               |
| --------------- | ---------------------------------------------------------------------- |
| シェル          | fish（機能別に分割した `conf.d` と自作関数）、tide プロンプト          |
| エディタ        | Neovim（lazy.nvim + Mason。`lua/my/` 名前空間で分割）                  |
| 端末            | tmux、alacritty、herdr、yazi                                           |
| Git             | `.gitconfig`、コミットテンプレート、lazygit / gitui                    |
| AI コーディング | Claude Code（skill / hook / statusline）、Codex                        |
| 作業自動化      | 日報・週次レポート・タスク起票を cron から headless で回すスクリプト群 |

## セットアップ

```fish
ghq get rhi222/dotfiles
cd (ghq root)/github.com/rhi222/dotfiles

bash scripts/setup/apt.sh   # apt パッケージ
./dotfilesLink.sh           # リンク作成 + 雛形生成 + git hook 有効化
```

**`dotfilesLink.sh` だけでは完了しない。** gitignore しているファイル（認証情報や環境固有の値）が別途要る。通し手順は [AGENTS.md](AGENTS.md) を参照。

## 開発

```fish
bash scripts/repository/lint.sh        # shellcheck + shfmt
bash scripts/repository/run-tests.sh   # 全テスト
bash scripts/repository/secret-scan.sh --tree
```

- 公開Shell APIは `scripts/`、内部実装は言語を問わず `internal/<feature>/` に置く
- Shellのblack-box testは `tests/<feature>/test-*.sh` に置く。`run-tests.sh` が自動で拾う
- CI で動かせないテストは、テストファイルの先頭付近に `# ci-skip: <理由>` と書いて宣言する
- lint は git が追跡している（＋未追跡で ignore されていない）`*.sh` すべてを対象にする

## このリポジトリは public

社名・社内ホスト名・社内リポジトリ名・Jira プロジェクトキー・案件コード・顧客略号は入れない。
それらは gitignore 対象のファイルかリポジトリ外に置き、ここにはプレースホルダ入りの `.example` だけを置く。

検査は2層で、commit 前の pre-commit hook（社内語を含む実辞書）と、push / PR 時の GitHub Actions（汎用パターンのみ）で行う。詳しくは AGENTS.md の「社内固有情報を入れない運用」を参照。

## ドキュメント

[AGENTS.md](AGENTS.md) が入口で、各機能の要点と「なぜそうしたか」を持つ（`CLAUDE.md` は同じファイルへの symlink）。
分量が大きく独立している話題は `docs/` に分けてある。

| 文書                                                                 | 中身                                                     |
| -------------------------------------------------------------------- | -------------------------------------------------------- |
| [docs/bootstrap.md](docs/bootstrap.md)                               | 新環境の立ち上げ手順と、gitignore しているファイルの台帳 |
| [docs/linear-command-layer.md](docs/linear-command-layer.md)         | Linear へのタスク集約とAI夜間ディスパッチ                |
| [docs/worktree.md](docs/worktree.md)                                 | `git wt` とworktreeの初期化・一覧・掃除                  |
| [docs/docker-clean.md](docs/docker-clean.md)                         | `dclean` の判定と閾値                                    |
| [docs/session-restore-strategy.md](docs/session-restore-strategy.md) | reboot 後のセッション復元の設計経緯                      |
