# 新環境の立ち上げ

新しい端末を、普段の作業に使える状態まで立ち上げるための手順。
gitignore している機密ファイルの移植台帳も兼ねる。

> [!IMPORTANT]
> `dotfilesLink.sh` だけではセットアップは完了しない。
> 認証情報や社内固有の値はリポジトリに含められないため、旧環境からのコピーや手入力が必要になる。

## 全体の流れ

上から順に進める。

1. リポジトリを取得し、基本セットアップを実行する
2. ローカル設定と機密ファイルを用意する
3. 外部ツールをインストールする
4. 必要な自動化を有効にする
5. lint・機密語スキャン・テストで確認する

WSL2 固有の作業には本文で明記している。それ以外の環境では該当箇所を飛ばす。

## 1. 基本セットアップを実行する

パスが `SNIPPET_ROOT` などに埋め込まれているため、このリポジトリは ghq 配下に置く。

```fish
ghq get rhi222/dotfiles
cd (ghq root)/github.com/rhi222/dotfiles

bash scripts/apt-setup.sh  # apt パッケージの導入（WSL2 のみ）
./dotfilesLink.sh          # リンク作成、雛形生成、hook 有効化
```

`dotfilesLink.sh` は次の雛形を `.example` ファイルから自動生成する。ただし、生成されるファイルの値は
空なので、[手順2](#2-ローカル設定と機密ファイルを用意する)で中身を埋める。

| ファイル                                 | 生成処理              | 埋める内容                                                        |
| ---------------------------------------- | --------------------- | ----------------------------------------------------------------- |
| `~/.config/dotfiles/secret-patterns.txt` | `setup_git_hooks`     | 社内固有の語。空のままだと機密語検出 hook が機能しない            |
| `~/.claude/local-context.md`             | `setup_local_configs` | Jira cloudId、プロジェクトキー、GitLab ホスト、esa チーム名、略号 |
| `.config/nvim/lua/my/local_config.lua`   | `setup_local_configs` | HTTPS 非対応ホスト                                                |
| `.config/codex/config.toml`              | `setup_codex`         | Codex のローカル設定                                              |

## 2. ローカル設定と機密ファイルを用意する

次の台帳で **A. 資格情報** と **B. 社内固有情報** をすべて確認する。
各項目の先頭にある移植方法は次の意味を持つ。

- **コピー** — 再作成が難しいため、旧環境からファイルやディレクトリを持ってくる
- **手書き** — 雛形が無いため、新環境でファイルを作成して値を記入する
- **雛形** — `dotfilesLink.sh` が作った空のファイルに値を記入する
- **自動** — セットアップ処理が配置する。内容だけ確認すればよい

### A. 資格情報

漏れるとすぐに悪用される可能性がある情報。値そのものはこの文書に記録しない。

- **コピー** `.config/AutoHotkey/ahk-snippets/passwords/` 配下5件
  — AWS・オペレータ・RDP の ID とパスワード。`README.md` と `.gitkeep` だけが追跡対象
- **手書き** `.config/fish/my/conf.d/99-local.fish`
  — esa の API トークンと `docker_clean_ignore_patterns`
- **手書き** `~/.config/linear/api-key`
  — Linear の API キー。作成後に `chmod 600 ~/.config/linear/api-key` を実行する
- **自動** `~/.claude/settings.json`
  — 社内 marketplace の定義を含む。`dotfilesLink.sh` が `sync-claude-settings.sh push` で配置し、
  同期時には機密値をマスクする

### B. 社内固有情報

社内のシステム構成や案件情報が分かる情報。これらも値そのものはこの文書に記録しない。

旧環境からコピーするもの：

- `.config/claude/skills/cross-repo-investigate/repos.yml`
  — 社内リポジトリのパスと日本語エイリアスの対応表
- `.config/claude/skills/cross-repo-auto-discover/`
  — ディレクトリごとコピーする。`repos.yml` は上記ファイルへの symlink
- `.config/claude/skills/esa-weekly-report/esa-weekly-report-posts.json`
  — 週次レポート対象の記事番号
- `.config/AutoHotkey/ahk-snippets/js/`
  — 社内システムの DOM 操作スクリプト
- `.config/AutoHotkey/scripts/snippets-local.ahk`
  — 上記スクリプトを登録する定義

`dotfilesLink.sh` が生成した雛形に値を入れるもの：

- `~/.claude/local-context.md`
  — Jira cloudId、プロジェクトキー、GitLab ホスト、esa チーム名、案件・顧客の略号
- `~/.config/dotfiles/secret-patterns.txt`
  — 機密語辞書。辞書自体が社内名の一覧になるため、リポジトリには含めない
- `.config/nvim/lua/my/local_config.lua`
  — HTTPS 非対応ホスト

手書きするもの：

- `.config/git/config-local`
  — 個人用の Git `user.*` と、必要なら業務用設定への `includeIf`
- `.config/git/config-work`
  — 業務用の Git `user.*`。個人用と分ける場合だけ作成する

Git 設定の具体例と注意点は[Git の user 設定](#git-の-user-設定)を参照。

### C. 機密を含まない ignore 対象

次のものは移植しなくてよい。

- `plans/`、`docs/superpowers/`、`.superpowers/` — 作業用スクラッチ
- `.config/tmux/plugins/`、`.config/yazi/plugins/` — プラグインマネージャが再取得する
- `.claude/skills/` — `setup-claude-skills.sh` が再取得する
- `.config/codex/config.toml` — 雛形から生成する
- `.config/nvim/pack`、`.netrwhist` — Neovim が生成する

### Git の user 設定

`user.*` は端末ごとに変わるため追跡しない。`.gitconfig` が常に読み込むのは `config-local` だけで、
業務用の設定は `config-local` の `includeIf` から `config-work` を読み込む二段構成にする。

`~/.config/git` は、このリポジトリの `.config/git/` への symlink になっている。
どちらのパスで編集しても実体は同じで、両ファイルとも `.gitignore` 済み。

#### 個人用設定（必須）

`~/.config/git/config-local` を作る。これが無い場合、`dotfilesLink.sh` は警告を出す。

```ini
[user]
	name = <個人アカウント名>
	email = <個人用メール>

# 業務用リポジトリ配下だけ user を差し替える
[includeIf "gitdir:/data/git-repos/<社内ホスト>/"]
	path = ~/.config/git/config-work
```

#### 業務用設定（必要な場合のみ）

`~/.config/git/config-work` を作る。

```ini
[user]
	name = <社内での表記>
	email = <業務用メール>
```

注意点：

- `gitdir:` の値には末尾のスラッシュを付ける。これにより、そのディレクトリ配下すべてにマッチする
- `/data/git-repos` は `.gitconfig` の `ghq.root`。`ghq get` したリポジトリはホスト名ごとに分かれる
- `git config --global` は使わない。`~/.gitconfig` は追跡ファイルへの symlink であり、Git は
  書き込み時に symlink の実体へ書くため、個人情報がリポジトリの `.gitconfig` に混入する
- 値を書き足すときは対象ファイルを明示する。例：
  `git config --file ~/.config/git/config-local user.email '<値>'`
- `config-work` が存在しなくても Git は警告しない。業務用リポジトリで個人用メールを使っていないか、
  次のコマンドで必ず確認する

値だけでなく設定元も確認できるよう、`--show-origin` を付ける。

```fish
git -C <個人リポジトリ> config --show-origin user.email  # config-local 由来になっていること
git -C <業務リポジトリ> config --show-origin user.email  # config-work 由来になっていること
git status --short .gitconfig .config/git/                # 出力が無いこと
```

## 3. 外部ツールをインストールする

ローカル設定を用意したら、リポジトリに宣言されている外部ツールを導入する。
`STRICT=1` を付けた処理は、一部のインストールに失敗した場合も成功扱いにせず終了する。

```fish
env STRICT=1 bash scripts/setup-claude-skills.sh  # 外部 agent skill
env STRICT=1 bash scripts/setup-gh-extensions.sh  # gh 拡張
bash scripts/linear-bootstrap.sh                  # Linear の team/state/label ID を解決
```

## 4. 自動化を有効にする（任意・WSL2）

使う機能だけ有効にする。各機能は、対応するフラグファイルを作らない限り動作しない。

| 機能                    | 有効化フラグ                           | cron の時刻                  |
| ----------------------- | -------------------------------------- | ---------------------------- |
| 日報リマインド通知      | `~/.config/nippo-notify-enabled`       | 平日 9・11・13・15・17・19時 |
| 日報ファイル自動作成    | `~/.config/nippo-create-enabled`       | 平日 8:00                    |
| 日報ドラフト自動仕上げ  | `~/.config/nippo-draft-enabled`        | 平日 18:30                   |
| esa 週次レポート        | `~/.config/esa-weekly-enabled`         | 金曜 16:00                   |
| Linear スイープ         | `~/.config/linear-sweep-enabled`       | 平日 8:00                    |
| Linear 夜間ディスパッチ | `~/.config/linear-dispatch-enabled`    | 火〜土曜 1:00                |
| Slack スタンプ起票      | `~/.config/linear-slack-sweep-enabled` | 平日 8:10                    |

実際に登録する cron エントリ：

```cron
0 9,11,13,15,17,19 * * 1-5 $HOME/scripts/nippo-cron.sh
0 8 * * 1-5 $HOME/scripts/nippo-create-cron.sh
30 18 * * 1-5 $HOME/scripts/nippo-draft-cron.sh
0 16 * * 5 $HOME/scripts/esa-weekly-cron.sh
0 8 * * 1-5 $HOME/scripts/linear-sweep.sh
0 1 * * 2-6 $HOME/scripts/linear-dispatch-cron.sh
10 8 * * 1-5 $HOME/scripts/linear-slack-sweep-cron.sh
```

フラグ作成前に、各機能の説明と手動確認方法を [AGENTS.md](../AGENTS.md) で確認する。

補足：

- headless の Claude を呼ぶ処理には、`lib/cron-claude.sh` で timeout を設定している。
  上限は `NIPPO_CREATE_TIMEOUT` など、機能ごとの環境変数で変更できる
- Windows トースト通知には、Windows 側で `Install-Module BurntToast` の実行が必要
- AutoHotkey は `bash .config/AutoHotkey/deploy-ahk-script.sh` で Windows 側へコピーする。
  `scripts/` 配下をすべてコピーするため、gitignore された `snippets-local.ahk` も対象になる

## 5. セットアップ結果を確認する

機密語辞書を埋めてから、次の3つをすべて実行する。

```fish
bash scripts/lint.sh                # shellcheck + shfmt（追跡・未追跡の全 .sh）
bash scripts/secret-scan.sh --tree  # 機密語スキャン
bash scripts/run-tests.sh           # 全テスト
```

最後に、普段使うリポジトリで Git のメールアドレスが正しく切り替わることも確認する。

---

この文書は [AGENTS.md](../AGENTS.md) から切り出した詳細手順。
AGENTS.md 側には概要と、この文書への入口だけを残している。
