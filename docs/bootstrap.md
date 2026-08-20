# 新環境の立ち上げ

新しい端末を、普段の作業に使える状態まで立ち上げるための手順。
gitignore している機密ファイルの移植台帳も兼ねる。

> [!IMPORTANT]
> `dotfilesLink.sh` だけではセットアップは完了しない。
> 認証情報や社内固有の値はリポジトリに含められないため、旧環境からのコピーや手入力が必要になる。

## 全体の流れ

上から順に進める。

0. 前提ツールを入れる
1. リポジトリを取得し、基本セットアップを実行する
2. ローカル設定と機密ファイルを用意する
3. 外部ツールをインストールする
4. 必要な自動化を有効にする
5. lint・機密語スキャン・テストで確認する

WSL2 固有の作業には本文で明記している。それ以外の環境では該当箇所を飛ばす。

## 0. 前提ツールを入れる

### インストール

**この3つだけはリポジトリの自動化では入らない。** どれも[手順1](#1-基本セットアップを実行する)の
中で使うものなので、先に手で入れる。この時点ではまだ fish がログインシェルではないので、
以下は bash で実行する。

```bash
sudo apt update && sudo apt install -y fish git curl
curl https://mise.run | sh
chsh -s /usr/bin/fish   # 反映のため一度ログインし直す
```

> [!WARNING]
> **この時点で `mise` は裸のコマンド名では通らない。** インストーラは `~/.local/bin/mise` に置くが、
> そこを PATH に足しているのは `00-paths.fish` で、**`dotfilesLink.sh` を走らせるまで存在しない**。
> 手順1の `exec fish` を抜けるまでは `~/.local/bin/mise` とフルパスで呼ぶ。

### 管理方法と例外

- **`fish` は `apt-packages.txt` にも書いてあるが、それを流す `apt-setup.sh` より前に要る。**
  手順1で重ねて入っても害は無い。宣言を残してあるのは、後から「何で入れたか」を追えるようにするため
- **`mise` が CLI ツールのほぼ全部を持ってくる。** gh・fzf・ripgrep・fd・tmux・neovim・yazi・
  ghq・git-wt・herdr・lazygit・shellcheck などは `.config/mise/config.toml` の宣言から入る。
  **apt で個別に入れない**（二重管理になり、`daily-update.sh` の更新対象からも外れる）
- **例外は `tig` だけで、これは `apt-packages.txt` に宣言してある。** mise にも aqua にも無く、
  GitHub リリースがソース tarball しか配っていないので `ubi` でも取れない
  （`tig-completion.bash has unknown extension` で落ちる）。**apt 版は 2.5.8 で upstream より古い。**
  新しい版が要るならソースビルドになるが、そのときは mise の管理外になることを承知して入れる
- **`ghq` もこの時点では無い。** 手順1の `ghq get` が使えるのは `mise install`（手順1の最後）の後なので、
  最初の1回だけは `git clone` でリポジトリを取る

## 1. 基本セットアップを実行する

### セットアップ手順

パスが `SNIPPET_ROOT` などに埋め込まれているため、このリポジトリは ghq 配下に置く。
`ghq` はまだ入っていないので、初回は `ghq root` と同じ場所へ手で clone する。

```fish
mkdir -p /data/git-repos/github.com/rhi222
git clone https://github.com/rhi222/dotfiles /data/git-repos/github.com/rhi222/dotfiles
cd /data/git-repos/github.com/rhi222/dotfiles

bash scripts/apt-setup.sh                                    # apt パッケージの導入（WSL2 のみ）
bash scripts/private-bundle.sh import ~/dotfiles-private.zip # 旧環境から運んだ集約ファイル
./dotfilesLink.sh                                            # リンク作成、雛形生成、hook 有効化
exec fish                                                    # リンクした設定を読み込む
mise install                                                 # config.toml のツールを一括導入
```

### 実行順序

**この3つの順序には理由があり、入れ替えると静かに壊れる。**

1. **`dotfilesLink.sh` が先。** `~/.config/mise/config.toml` はリンクで配置されるので、
   先に `mise install` すると宣言そのものが見つからない。`dotfilesLink.sh` 自体は
   リンクを張るだけで `mise install` は呼ばないため、ここで明示的に実行する
2. **`exec fish` が次。** リンクされた `my/conf.d/*.fish` がここで初めて読まれ、
   `00-paths.fish` が `~/.local/bin` を PATH に入れ、`01-mise.fish` が
   `MISE_*_DEFAULT_PACKAGES_FILE` を設定する
3. **`mise install` が最後。** **2 より前に走らせると、ランタイムは入るが
   `.default-python-packages` / `.default-npm-packages` の中身が入らない。**
   場所を教えているのが 2 で設定される環境変数だけだからで、mise は黙って成功する。
   `pynvim` が落ちて nvim の `:checkhealth` が Python provider を ERROR にする、
   といった形で後から気づくことになる

### mise の確認と復旧

`mise --version` が返らない場合は、`~/.local/bin` が `$fish_user_paths` に入っているかを
`echo $fish_user_paths` で確認する。PATH を足す `00-paths.fish` は `01-mise.fish` より
前に読ませる必要があり（番号がそのまま依存順になる）、逆順だと `type -q mise` が偽になって
mise が activate されない。

既に default packages 抜きで入れてしまった場合は、環境変数が入った状態で入れ直す。

```fish
mise install --force python node
```

### private bundle と雛形

**旧環境が生きているなら、[手順2](#2-ローカル設定と機密ファイルを用意する)の移植作業はこの
`import` で終わる。** 旧環境が無い場合は `import` を飛ばし、手順2で雛形に値を書く。

集約ファイルを import していない場合、`dotfilesLink.sh` は次の雛形を `.example` ファイルから
自動生成する。ただし、生成されるファイルの値は空なので、手順2で中身を埋める。
import 済みなら実体が既にあるので、雛形生成はスキップされる。

| ファイル                                 | 生成処理              | 埋める内容                                                        |
| ---------------------------------------- | --------------------- | ----------------------------------------------------------------- |
| `~/.config/dotfiles/secret-patterns.txt` | `setup_git_hooks`     | 社内固有の語。空のままだと機密語検出 hook が機能しない            |
| `~/.claude/local-context.md`             | `setup_local_configs` | Jira cloudId、プロジェクトキー、GitLab ホスト、esa チーム名、略号 |
| `.config/nvim/lua/my/local_config.lua`   | `setup_local_configs` | HTTPS 非対応ホスト                                                |
| `.config/codex/config.toml`              | `setup_codex`         | Codex のローカル設定                                              |

## 2. ローカル設定と機密ファイルを用意する

> [!TIP]
> **旧環境が生きているなら、この節の手作業はすべて `import` 1回で終わる。**
> 以下の台帳は「集約ファイルに何が入っているか」の記録として残している。
> 旧環境が無い立ち上げでのみ、コピーや手書きが必要になる。

### 旧環境がある場合：集約ファイルで運ぶ

旧環境で1度だけ集約し、zip に固めて運ぶ。

```fish
# 旧環境で
bash scripts/private-bundle.sh adopt            # dry-run。何が動くか確認する
bash scripts/private-bundle.sh adopt --execute  # 集約先へ移して symlink 化
bash scripts/private-bundle.sh export           # ~/dotfiles-private-YYYYMMDD.zip

# 新環境で
bash scripts/private-bundle.sh import ~/dotfiles-private-YYYYMMDD.zip
./dotfilesLink.sh
bash scripts/private-bundle.sh status           # 全項目がリンク済みであること
```

集約先は `~/.local/share/dotfiles-private/` で、`home/` と `repo/` の2ルートに
`$HOME`・リポジトリルートからの相対パスをそのまま再現する。**実体は集約先にあり、
各所へは `dotfilesLink.sh` が symlink を張る。** どこを編集しても集約先が最新になるので、
`export` はいつ走らせてもよい。

`~/.claude/settings.json` はこの仕組みの対象外。`sync-claude-settings.sh` がマスクしながら
コピー同期する（[AGENTS.md](../AGENTS.md) 参照）。

### 旧環境がない場合：台帳から用意する

次の台帳で **A. 資格情報** と **B. 社内固有情報** をすべて確認する。
各項目の先頭にある移植方法は次の意味を持つ。

- **コピー** — 再作成が難しいため、旧環境からファイルやディレクトリを持ってくる
- **手書き** — 雛形が無いため、新環境でファイルを作成して値を記入する
- **雛形** — `dotfilesLink.sh` が作った空のファイルに値を記入する
- **自動** — セットアップ処理が配置する。内容だけ確認すればよい
- **再ログイン** — コピー不要。新環境で各ツールにログインし直せば復旧する

#### A. 資格情報

漏れるとすぐに悪用される可能性がある情報。値そのものはこの文書に記録しない。

- **コピー** `~/.ssh/`
  — GitHub（個人・業務）・GitLab・Backlog の鍵、AWS の `.pem`、`config`。
  ディレクトリごと運び、秘密鍵のパーミッションが 600 であることを確認する
- **コピー** `~/.aws/`
  — AWS CLI / SSO の設定と認証情報。**中身は開かずディレクトリごとコピーする**
  （AI に読ませない領域。この台帳にも値やプロファイル名を書かない）
- **コピー** `~/.claude/settings.local.json`
  — esa MCP サーバー定義（API トークンを平文で含む）。`sync-claude-settings.sh` が
  同期するのは `settings.json` だけで、このファイルは対象外
- **コピー** `.config/AutoHotkey/ahk-snippets/passwords/` 配下5件
  — AWS・オペレータ・RDP の ID とパスワード。`README.md` と `.gitkeep` だけが追跡対象
- **再ログイン** Claude Code（初回起動時にログイン）・Codex CLI（`codex login`。
  `~/.codex/auth.json` のコピーでも可）・gh（`gh auth login`）
- **手書き** `.config/fish/my/conf.d/99-local.fish`
  — esa の API トークンと `docker_clean_ignore_patterns`
- **手書き** `~/.config/linear/api-key`
  — Linear の API キー。作成後に `chmod 600 ~/.config/linear/api-key` を実行する
- **自動** `~/.claude/settings.json`
  — 社内 marketplace の定義を含む。`dotfilesLink.sh` が `sync-claude-settings.sh push` で配置し、
  同期時には機密値をマスクする

#### B. 社内固有情報

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

Git 設定の具体例と注意点は[Git の user 設定](#git-の-user-設定を分ける)を参照。

#### C. 機密を含まない ignore 対象

次のものは移植しなくてよい。

- `plans/`、`docs/superpowers/`、`.superpowers/` — 作業用スクラッチ
- `.config/tmux/plugins/`、`.config/yazi/plugins/` — プラグインマネージャが再取得する。
  ただし **tpm 自身はこの中に入っている**ので、tmux 側だけ[手順3](#宣言が無く手で入れるもの)で手動 clone する
- `.claude/skills/` — `setup-claude-skills.sh` が再取得する
- `.config/codex/config.toml` — 雛形から生成する
- `.config/nvim/pack`、`.netrwhist` — Neovim が生成する

### Git の user 設定を分ける

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

#### 注意点

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

### リポジトリの宣言から入れる

ローカル設定を用意したら、リポジトリに宣言されている外部ツールを導入する。
`STRICT=1` を付けた処理は、一部のインストールに失敗した場合も成功扱いにせず終了する。

```fish
env STRICT=1 bash scripts/setup-claude-skills.sh  # 外部 agent skill
env STRICT=1 bash scripts/setup-gh-extensions.sh  # gh 拡張
bash scripts/linear-bootstrap.sh                  # Linear の team/state/label ID を解決
```

### 宣言が無く、手で入れるもの

**次のものはリポジトリのどこにも宣言が無い。** 設定だけがリンクされて中身が伴わない状態になり、
しかも起動はするので気づきにくい。使う分を手で入れる。

- **fisher + fish プラグイン** — プロンプト（tide）と Ctrl+R（fzf.fish）の実体。
  入れないと `05-tide-settings.fish` や `10-fzf.fish` が読まれても何も起きない
- **tmux tpm** — `tmux.conf` の `@plugin` 宣言が全て無効になる。tmux を使う場合のみ
- **Claude Code** — `.config/claude/` 配下の hook と skill、[手順4](#4-自動化を有効にする任意wsl2)の
  cron 自動化がすべてこれに乗っている
- **Codex CLI** — `npm i -g @openai/codex`。`.config/codex/` と `~/.agents/skills/` の自作 skill 用
- **Docker** — Docker Desktop の WSL2 統合を有効にする（統合を使わない場合は docker apt repo）。
  `dclean`・`dc` 系の略語・`lazydocker` が依存する

#### fisher と fish プラグイン

**`~/.config/fish/fish_plugins` は追跡していない**ので、プラグインは名指しで入れ直す。

```fish
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
fisher install jorgebucaran/fisher ilancosman/tide@v6 patrickf1/fzf.fish
tide configure --auto \
    --style=Lean \
    --prompt_colors='True color' \
    --show_time='24-hour format' \
    --lean_prompt_height='One line' \
    --prompt_spacing=Compact \
    --icons='Few icons' \
    --transient=No
exec fish
```

**対話の `tide configure` は使わない。** tide の見た目は156個の universal 変数で決まるが、
`fish_variables` は追跡していないので、リポジトリ側にあるのは `05-tide-settings.fish` が
`set -g` する2つ（`tide_prompt_min_cols` / `tide_right_prompt_items`）だけ。
残り154個はウィザードの回答そのもので、**答えを間違えるか質問を飛ばすと別の見た目になる**。
`--auto` は同じ回答を引数で渡すので、何度流しても同じ154個が確定する。

飛ばした場合に出るのは lean プリセットの既定（`tide_left_prompt_items` が
`pwd git newline character`、`tide_prompt_add_newline_before` が `true`）で、
**空行 + 情報行 + `❯` の3行プロンプト**になる。ここが1行になっていない端末は、この手順を
踏んでいない端末。

#### Claude Code

Claude Code は公式インストーラで入れる。**npm でも mise でもない**ので、宣言リストには載らない。

```fish
curl -fsSL https://claude.ai/install.sh | bash
exec fish        # ~/.local/bin が PATH に入っていること
claude --version
claude           # 初回はログインが要る
```

#### tmux tpm

`~/.config/tmux/plugins/` も追跡していない。tpm だけ手で clone し、残りは tmux 内から取る。

```fish
git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
# tmux を起動して prefix + I（大文字）で tmux.conf の @plugin を一括取得
```

#### 手動インストール後の補足

- **セッション復元は herdr が持っており、tmux-resurrect / tmux-continuum は使わない。**
  `tmux.conf` の宣言からは外してある。ただし **tpm は宣言から消しても実体を消さない**ので、
  旧環境の `plugins/` を持ち込んだ場合は `prefix + alt+u` で刈る
- Claude Code のインストーラは `~/.local/bin/claude` を
  `~/.local/share/claude/versions/<ver>` への symlink として置く。**mise の管理外**なので、
  更新も `daily-update.sh` ではなく Claude Code 自身が行う
- **Claude Code を入れないと[手順4](#4-自動化を有効にする任意wsl2)の cron が全滅する。**
  日報・Linear・esa 週次はすべてヘッドレスの `claude` を呼んでいる
- Neovim のプラグインと LSP は初回起動時に lazy.nvim と Mason が入れるため、明示的な操作は要らない

### Windows 側の設定を反映する（WSL2）

`.wslconfig` と Windows Terminal の `settings.json` は `/mnt/c` にあり symlink できないので、
`dotfilesLink.sh` の対象外になっている。**内容を確認してから手で押し出す。**

```fish
bash scripts/sync-windows-settings.sh status          # 実ファイルとの差分
bash scripts/sync-windows-settings.sh push --force    # リポジトリ -> 実ファイル
wsl.exe --shutdown                                    # .wslconfig の反映（Windows 側から）
```

- **`.wslconfig` は値をそのまま使わない。** `memory=12GB` は「物理32GB・Windows 側の
  commit 約21GB」という**この端末の実測から出した値**で、スペックが違えば適切な値も変わる。
  ファイル内のコメントに導出過程を残してあるので、それを読んで新しい端末の数字で決め直す
- Windows Terminal 側はフォントに `HackGen Console NF` と `Consolas NF` を指定している。
  **Windows にこの2つを入れておかないと豆腐になる**（Nerd Font 版が必要）
- プロファイルの GUID は distro 名から決定的に生成されるので、同じ `Ubuntu` を使う限り
  そのまま通る。別名の distro を入れた端末では Terminal 側が新しい行を足すので、
  その後 `pull` してリポジトリを追随させる

## 4. 自動化を有効にする（任意・WSL2）

### 有効化する機能を選ぶ

使う機能だけ有効にする。各機能は、対応するフラグファイルを作らない限り動作しない。

| 機能                    | 有効化フラグ                           | cron の時刻                  |
| ----------------------- | -------------------------------------- | ---------------------------- |
| 日報リマインド通知      | `~/.config/nippo-notify-enabled`       | 平日 9・11・13・15・17・19時 |
| 日報ファイル自動作成    | `~/.config/nippo-create-enabled`       | 平日 8:00                    |
| 日報ドラフト自動仕上げ  | `~/.config/nippo-draft-enabled`        | 平日 18:30                   |
| esa 週次レポート        | `~/.config/esa-weekly-enabled`         | 金曜 16:00                   |
| Linear スイープ         | `~/.config/linear-sweep-enabled`       | 平日 8:00                    |
| Linear 夜間ディスパッチ | `~/.config/linear-dispatch-enabled`    | 火〜土曜 1:00                |
| Slack スタンプ起票      | `~/.config/linear-slack-sweep-enabled` | 平日 10:10                   |

### cron を登録する

**フラグを作った機能の行だけ**登録する（全行を入れる必要はない）。
逆に、**フラグと cron は必ずセットで揃える。** フラグだけ作って cron を忘れると
機能が黙って止まる（linear-dispatch で実際に起きた。フラグは何も実行しない）。

```cron
0 9,11,13,15,17,19 * * 1-5 $HOME/scripts/nippo-cron.sh >> $HOME/.nippo-cron.log 2>&1
0 8 * * 1-5 $HOME/scripts/nippo-create-cron.sh >> $HOME/.nippo-create-cron.log 2>&1
30 18 * * 1-5 $HOME/scripts/nippo-draft-cron.sh >> $HOME/.nippo-draft-cron.log 2>&1
0 16 * * 5 $HOME/scripts/esa-weekly-cron.sh >> $HOME/.esa-weekly-cron.log 2>&1
0 8 * * 1-5 $HOME/scripts/linear-sweep.sh >> $HOME/.linear-sweep.log 2>&1
0 1 * * 2-6 $HOME/scripts/linear-dispatch-cron.sh >> $HOME/.linear-dispatch.log 2>&1
10 10 * * 1-5 $HOME/scripts/linear-slack-sweep-cron.sh >> $HOME/.linear-slack-sweep.log 2>&1
```

フラグ作成前に、各機能の説明と手動確認方法を [AGENTS.md](../AGENTS.md) で確認する。

### 旧環境の crontab を運ぶ

crontab には dotfiles 管理外のエントリ（社内向けの集計ジョブ等）も入っているため、
上の表だけでは復元できない。旧環境で全文を private 集約先に退避し、新環境で読み戻す。

```fish
# 旧環境で。集約先ルート直下は export の zip に入るが、home/ 配下ではないので
# dotfilesLink.sh のリンク対象にはならない
crontab -l > ~/.local/share/dotfiles-private/crontab.txt

# 新環境で（import 後、中身を確認してから）
crontab ~/.local/share/dotfiles-private/crontab.txt
```

### 補足

- headless の Claude を呼ぶ処理には、`lib/cron-claude.sh` で timeout を設定している。
  上限は `NIPPO_CREATE_TIMEOUT` など、機能ごとの環境変数で変更できる
- Windows トースト通知には、Windows 側で `Install-Module BurntToast` の実行が必要
- AutoHotkey は `bash .config/AutoHotkey/deploy-ahk-script.sh` で Windows 側へコピーする。
  `scripts/` 配下をすべてコピーするため、gitignore された `snippets-local.ahk` も対象になる

## 5. セットアップ結果を確認する

機密語辞書を埋めてから、次の3つをすべて実行する。

```fish
bash scripts/private-bundle.sh status  # ローカル設定が全てリンク済みか
bash scripts/lint.sh                   # shellcheck + shfmt（追跡・未追跡の全 .sh）
bash scripts/secret-scan.sh --tree     # 機密語スキャン
bash scripts/run-tests.sh              # 全テスト
```

最後に、普段使うリポジトリで Git のメールアドレスが正しく切り替わることも確認する。

---

この文書は [AGENTS.md](../AGENTS.md) から切り出した詳細手順。
AGENTS.md 側には概要と、この文書への入口だけを残している。
