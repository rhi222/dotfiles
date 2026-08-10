# 新環境の立ち上げ

新しい端末をゼロから使える状態にするまでの通し手順と、gitignore しているファイルの台帳。

**`dotfilesLink.sh` だけでは完了しない。** gitignore しているファイルが必要で、その多くは
雛形が無く旧環境からのコピーか手書きになる。以下の順で進める。

## 1. 前提を入れる

```fish
# ghq でこのリポジトリを取得（パスが SNIPPET_ROOT 等に埋まっているので ghq 配下に置く）
ghq get rhi222/dotfiles
cd (ghq root)/github.com/rhi222/dotfiles

bash scripts/apt-setup.sh          # apt パッケージ（WSL2）
./dotfilesLink.sh                  # リンク作成 + 雛形生成 + hook 有効化
```

`dotfilesLink.sh` が**自動で雛形を作る**のは次の4つ。**いずれも中身は空なので値を埋める。**

| ファイル | 作る処理 | 埋める内容 |
| --- | --- | --- |
| `~/.config/dotfiles/secret-patterns.txt` | `setup_git_hooks` | 社内固有の語（これが無いと hook がザルになる） |
| `~/.claude/local-context.md` | `setup_local_configs` | Jira cloudId・プロジェクトキー・GitLabホスト・esaチーム名・略号 |
| `.config/nvim/lua/my/local_config.lua` | `setup_local_configs` | HTTPS 非対応ホスト |
| `.config/codex/config.toml` | `setup_codex` | codex の設定 |

## 2. 雛形が無いファイルを移植する

対象は下の「機密ファイル台帳」の A と B。移植方法は3種類ある。

| 記号 | 意味 |
| --- | --- |
| **コピー** | 旧環境から持ってくる。再作成が非現実的（社内リポジトリ一覧・JS本体・資格情報など） |
| **手書き** | 雛形が無いので手で書く |
| **雛形** | `dotfilesLink.sh` が `.example` から作る。**中身は空なので値を埋める** |

## 機密ファイル台帳

**値そのものはここに書かない。** どこに何があるかと、移植方法だけを記録する。
`.gitignore` の全エントリのうち、機密を含むものを機微度で3段に分けた。

**A. 資格情報**（漏れると即座に悪用される）

| パス | 中身 | 移植 |
| --- | --- | --- |
| `.config/AutoHotkey/ahk-snippets/passwords/` 配下5件 | AWS・オペレータ・RDP の ID とパスワード（`README.md` と `.gitkeep` だけ追跡） | コピー |
| `.config/fish/my/conf.d/99-local.fish` | esa の APIトークン、`docker_clean_ignore_patterns` | 手書き |
| `~/.config/linear/api-key` | Linear の APIキー（`chmod 600`） | 手書き |
| `~/.claude/settings.json` | 社内 marketplace の定義を含む | `dotfilesLink.sh` が push（`sync-claude-settings.sh` がマスク） |

**B. 社内固有情報**（システム構成が露出する）

| パス | 中身 | 移植 |
| --- | --- | --- |
| `.config/claude/skills/cross-repo-investigate/repos.yml` | 社内リポジトリのパスと日本語エイリアスの対応表 | コピー |
| `.config/claude/skills/cross-repo-auto-discover/` | ディレクトリごと（`repos.yml` は上への symlink） | コピー |
| `.config/claude/skills/esa-weekly-report/esa-weekly-report-posts.json` | 週次レポート対象の記事番号 | コピー |
| `.config/AutoHotkey/ahk-snippets/js/` | 社内システムの DOM 操作スクリプト | コピー |
| `.config/AutoHotkey/scripts/snippets-local.ahk` | 上を登録する定義 | コピー |
| `~/.claude/local-context.md` | Jira cloudId・プロジェクトキー・GitLabホスト・esaチーム名・案件/顧客略号 | 雛形 |
| `~/.config/dotfiles/secret-patterns.txt` | 機密語辞書（＝社内名の一覧そのもの） | 雛形 |
| `.config/nvim/lua/my/local_config.lua` | HTTPS 非対応ホスト | 雛形 |
| `.config/git/config-local` | git の `user.*`。`.gitconfig` が `include` しているので無いと警告が出る | 手書き |
| `.config/git/config-work` | 業務用 git 設定 | 手書き |

**C. 機密を含まない ignore**（移植不要）

`plans/` / `docs/superpowers/` / `.superpowers/`（作業用スクラッチ）、
`.config/tmux/plugins/` / `.config/yazi/plugins/`（プラグインマネージャが再取得）、
`.claude/skills/`（`setup-claude-skills.sh` が再取得）、
`.config/codex/config.toml`（雛形あり）、`.config/nvim/pack` / `.netrwhist`（nvim が作る）

## 3. 外部ツールを入れる

```fish
env STRICT=1 bash scripts/setup-claude-skills.sh   # 外部 agent skill
env STRICT=1 bash scripts/setup-gh-extensions.sh   # gh 拡張
bash scripts/linear-bootstrap.sh                   # Linear の team/state/label ID 解決
```

## 4. 自動化を有効にする（任意・WSL2）

**フラグを touch しないと動かない。** 各機能の詳細は後続の該当節を参照。

| 機能 | フラグ | cron |
| --- | --- | --- |
| 日報リマインド通知 | `~/.config/nippo-notify-enabled` | `0 9,11,13,15,17,19 * * 1-5 $HOME/scripts/nippo-cron.sh` |
| 日報ファイル自動作成 | `~/.config/nippo-create-enabled` | `0 8 * * 1-5 $HOME/scripts/nippo-create-cron.sh` |
| 日報ドラフト自動仕上げ | `~/.config/nippo-draft-enabled` | `30 18 * * 1-5 $HOME/scripts/nippo-draft-cron.sh` |
| esa週次レポート | `~/.config/esa-weekly-enabled` | `0 16 * * 5 $HOME/scripts/esa-weekly-cron.sh` |
| Linear スイープ | `~/.config/linear-sweep-enabled` | `0 8 * * 1-5 $HOME/scripts/linear-sweep.sh` |
| Linear 夜間ディスパッチ | `~/.config/linear-dispatch-enabled` | `0 1 * * 2-6 $HOME/scripts/linear-dispatch-cron.sh` |
| Slackスタンプ起票 | `~/.config/linear-slack-sweep-enabled` | `10 8 * * 1-5 $HOME/scripts/linear-slack-sweep-cron.sh` |

**headless の Claude を呼ぶものには全て timeout が掛かっている**（`lib/cron-claude.sh`）。
誰も見ていない時間に走るので、ハングを放置すると次の起動まで残る。上限は仕事の重さで
変えてあり、`NIPPO_CREATE_TIMEOUT` のような環境変数で上書きできる。

Windowsトースト通知には Windows 側で `Install-Module BurntToast` が別途必要。
AutoHotkey は `bash .config/AutoHotkey/deploy-ahk-script.sh` で Windows 側へコピーする
（`scripts/` 配下を全部コピーするので、gitignore された `snippets-local.ahk` も届く）。

## 5. 確認する

```fish
bash scripts/lint.sh                # shellcheck + shfmt（追跡＋未追跡の全 .sh）
bash scripts/secret-scan.sh --tree  # 機密語スキャン（辞書を埋めた後に）
bash scripts/run-tests.sh           # 全テスト
```

---

この文書は [AGENTS.md](../AGENTS.md) から切り出したもの。AGENTS.md 側には要点と入口だけを残してある。
