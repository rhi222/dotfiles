# AGENTS.md

## リポジトリ概要

各種開発ツールやアプリケーションの設定ファイルを含む個人用dotfilesリポジトリです。シンボリックリンクを使用して、異なるシステム間で設定ファイルを管理しています。

**このファイルは全機能の要点と「なぜそうしたか」を持つ。** 分量が大きく独立している話題は
`docs/` に分けてあり、ここには要約と入口だけを残している。**必要になったときに開けばよく、
先に全部読む必要はない。**

| 文書                                                                 | いつ開くか                                           |
| -------------------------------------------------------------------- | ---------------------------------------------------- |
| [docs/bootstrap.md](docs/bootstrap.md)                               | 新しい端末を立ち上げるとき。機密ファイルの台帳もここ |
| [docs/linear-command-layer.md](docs/linear-command-layer.md)         | Linear の起票規約・Cycle・夜間ディスパッチを触るとき |
| [docs/worktree.md](docs/worktree.md)                                 | worktree の初期化・掃除の判定を変えるとき            |
| [docs/session-restore-strategy.md](docs/session-restore-strategy.md) | `he` の復元（herdr / nvim / claude）を触るとき       |
| [docs/docker-clean.md](docs/docker-clean.md)                         | `dclean` の判定や閾値を変えるとき                    |

## セットアップとインストール

### 新環境の立ち上げ

**`dotfilesLink.sh` だけでは完了しない。** gitignore しているファイル（認証情報・社内固有の値）が
別途必要で、その多くは雛形が無く旧環境からのコピーか手書きになる。

```fish
ghq get rhi222/dotfiles          # パスが SNIPPET_ROOT 等に埋まっているので ghq 配下に置く
cd (ghq root)/github.com/rhi222/dotfiles
bash scripts/apt-setup.sh        # apt パッケージ（WSL2）
./dotfilesLink.sh                # リンク作成 + 雛形生成 + hook 有効化
```

この後に必要な移植作業・外部ツールの導入・自動化の有効化と、**機密ファイル台帳**（どのファイルが
何を持ち、コピー / 手書き / 雛形のどれで用意するか）は [docs/bootstrap.md](docs/bootstrap.md)。

確認は次の3つ。

```fish
bash scripts/lint.sh                # shellcheck + shfmt（追跡＋未追跡の全 .sh）
bash scripts/secret-scan.sh --tree  # 機密語スキャン（辞書を埋めた後に）
bash scripts/run-tests.sh           # 全テスト
```

### メインセットアップスクリプト

`./dotfilesLink.sh` を実行して、すべての設定ファイルのシンボリックリンクを作成：

- Git設定 (`.gitconfig`, `.config/git/`)
- Neovim設定 (`.config/nvim/`)
- Fish shell設定 (`.config/fish/`)
- ターミナルマルチプレクサ (`.config/tmux/`)
- 開発ツール (mise, lazygit, gitui, etc.)
- Claude Code設定 (`.config/claude/`)

`~/.claude/settings.json` だけは例外でリンクせずコピー同期する（次節）。

### Claude Code settings.json の同期

`~/.claude/settings.json` は **シンボリックリンクにしない**。Claude Code が `/config` でのテーマ変更・プラグインの有効無効・`skillOverrides` などを実行時に書き戻すとき、一時ファイル + rename で置き換えるためリンクが必ず外れて実ファイル化する。`CLAUDE.md` や `commands/` は書き込まれないのでリンクのままでよい。

そこで `scripts/sync-claude-settings.sh` でコピー同期する。**実ファイルを正とし、リポジトリがそれを追いかける**。

| やりたいこと            | コマンド                                      |
| ----------------------- | --------------------------------------------- |
| 差分の確認              | `bash scripts/sync-claude-settings.sh status` |
| 実ファイル → リポジトリ | `bash scripts/sync-claude-settings.sh pull`   |
| リポジトリ → 実ファイル | `bash scripts/sync-claude-settings.sh push`   |
| 新環境 bootstrap        | `./dotfilesLink.sh`（内部で `push` する）     |
| 更新                    | `daily-update.sh` が `pull` を自動実行        |

- 保存時に `jq -S` でキー順を正規化するので、差分は常に意味のある変更だけになる
- `push` は実ファイルとリポジトリに差分があると既定で拒否する。`/config` での変更を消さないため。上書きしてよいときだけ `push --force`
- 不正なJSONは相手側へ伝播させずに失敗する
- `daily-update.sh` の `pull` は作業ツリーに差分を出すだけ。コミットするかは人間が判断する

動作確認は `bash scripts/test-sync-claude-settings.sh`。

### statusline（ccstatusline）

statusline は `ccstatusline`（`settings.json` の `statusLine.command`）で描画し、レイアウトは
`.config/ccstatusline/settings.json` で管理する（`dotfilesLink.sh` がリンクする）。

1行目のモデル名だけは標準の `model` ウィジェットを使わず、`custom-command` ウィジェットから
`.config/claude/scripts/statusline-model.sh` を呼んでいる。**標準の `model` ウィジェットは色が
固定値で、モデルによって見た目を変えられないため。** `custom-command` は stdin に Claude Code の
statusline JSON をそのまま渡し、`preserveColors: true` なら stdout の ANSI を保持するので、
スクリプト側で配色を出し分けられる。

| モデル   | 表示                                                        |
| -------- | ----------------------------------------------------------- |
| Fable    | `⚡FABLE 5⚡`（オリーブ背景・カーキ文字・太字の反転バッジ） |
| それ以外 | `Model: <名前>`（cyan。標準ウィジェットと同じ見た目）       |

- **Fable 判定は `model.id` の前方一致（`claude-fable*`）と `display_name` の部分一致の両方で行う。** `display_name` の実際の表記を実機で確認できていないため、どちらか一方でも拾えるようにしている
- バッジの配色は低彩度に寄せる（背景 `48;5;58` / 文字 `38;5;186`）。純色の黄背景（`48;5;226`）は目に痛く、他ウィジェット（`96` / `59` / `178`）の系統からも浮くため
- `display_name` が無ければ `model.id` を使い、末尾の `(1M context)` のような括弧書きは落とす（標準ウィジェットと同じ挙動に合わせている）
- `jq` が無い環境では `Model: ?` を返して exit 0 する。statusline 全体を壊さないため、この経路では外部コマンドを一切呼ばない
- 実行時間は約32ms/回。`timeout` は 3000ms に設定している

動作確認は `bash scripts/test-statusline-model.sh`。見た目は statusline JSON を流し込んで確認する。

```fish
echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"workspace":{"current_dir":"."}}' | ccstatusline
```

### 日次アップデート（daily-update.sh）

`scripts/daily-update.sh` が各パッケージマネージャとツールの更新をまとめて回す。
apt / cargo / mise（self-update・upgrade・prune）/ npm global / pip global /
nvim の Lazy と Mason / gh skill / gh extension / yazi プラグインの順に実行し、最後に
worktree の溜まり込みチェックと `sync-claude-settings.sh pull` を行う。

- **1ステップの失敗で止めない。** 全部走らせてから、失敗したステップ名をまとめて報告する
- **「更新」と「情報提供」を区別する。** worktree のチェックは `run_step_soft` で実行し、
  `gh` 未認証などで失敗しても全体を FAILED にしない。毎日 FAILED 通知が飛ぶと無視されるようになるため
- 失敗があれば Windowsトースト通知を出す（WSL2以外ではスキップ）
- ログは `~/.daily-update/` に日次で残り、**30日より古いものは起動時に掃除する**
- 冒頭で mise の shim を PATH 前方に置き直す。長時間動いている親シェルから継承した
  バージョン固定の PATH のままだと、`mise upgrade` 後に古い `installs/<tool>/<ver>/` を
  掴んだままになる（`gh` がこれで `/usr/bin/gh` に落ちて `gh skill` を失った実例がある）
- 新規追加はここではやらない。skill は `skill-add.sh`、gh 拡張は `gh-extensions.txt` +
  `setup-gh-extensions.sh`、yazi プラグインは `ya pkg add` + `setup-yazi-plugins.sh` の担当で、
  ここは既存のものの更新だけを回す
- **yazi プラグインは `package.toml` が無い端末では何もせず成功扱いにする。** yazi を入れていない
  環境で毎日 FAILED が出ないようにするため（他のステップと違い、宣言ファイルの有無で判定できる）

動作確認は `bash scripts/test-daily-update.sh`。

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

| やりたいこと     | コマンド                                                                          |
| ---------------- | --------------------------------------------------------------------------------- |
| 拡張追加         | `gh-extensions.txt` に `<owner>/<repo>[@<version>]` を追記 → 下の一括インストール |
| 一括インストール | `bash scripts/setup-gh-extensions.sh`（インストール済みはskip）                   |
| 新環境 bootstrap | `env STRICT=1 bash scripts/setup-gh-extensions.sh`                                |
| 更新             | `daily-update.sh` が `gh extension upgrade --all` を実行                          |
| 削除             | `gh-extensions.txt` の行削除 + `gh extension remove <name>`                       |

`@<version>` を付けるとそのリリースタグに `--pin` する。動作確認は `bash scripts/test-gh-extensions.sh`。

### yaziプラグイン管理

yazi のプラグインは `ya`（yazi 同梱のCLI）で管理し、宣言リストは `.config/yazi/package.toml`。
実体の `.config/yazi/plugins/` は gitignore していて、upstream のコードはリポジトリに抱えない。

| やりたいこと     | コマンド                                                        |
| ---------------- | --------------------------------------------------------------- |
| プラグイン追加   | `ya pkg add <owner/repo>[:<name>]`（package.toml も更新される） |
| 一括インストール | `bash scripts/setup-yazi-plugins.sh`（実体が揃っていればskip）  |
| 新環境 bootstrap | `./dotfilesLink.sh` が自動実行                                  |
| 更新             | `daily-update.sh` が `ya pkg upgrade` を実行                    |
| 削除             | `ya pkg delete <name>`                                          |

- **これだけは `dotfilesLink.sh` から自動で呼ぶ。** gh 拡張や skill は無ければ機能が欠けるだけだが、
  yazi は `init.lua` が `require("git")` するので**実体が無いと起動そのものが exit 1 で落ちる**
  （`Failed to load plugin from .../git.yazi/main.lua`）。リンクを張っただけの新環境で必ず踏む
- **`ya pkg add` は宣言と実体を同時に作る。** そのため追加した端末では動き、他の端末では壊れる。
  宣言だけが git に乗るので、実体を配置する経路が別に必要になる
- **`ya` の終了コードを信じない。** install が成功しても実体が入っていなければ失敗として扱う。
  「宣言はあるが `plugins/` が空」が起動不能の状態そのもので、そこを検知しないと意味がない
- **既に揃っているときは `ya pkg install` を呼ばない。** bootstrap のたびに走るので、
  健全な端末ではネットワークに出ないようにする
- `package.toml` は `rev` と `hash` を持ち lockfile を兼ねる。`ya pkg install` はこの rev に固定して取る。
  `ya pkg upgrade` はここを書き換えるので作業ツリーに差分が出るが、コミットするかは人間が判断する
- 設定ディレクトリは `ya` と同じ順（`YAZI_CONFIG_HOME` → `XDG_CONFIG_HOME/yazi` → `~/.config/yazi`）で解決する

動作確認は `bash scripts/test-yazi-plugins.sh`。

### Windowsトースト通知（WSL2専用）

Claude Code のフックと cron から、Windows側の `BurntToast` (PowerShell) でトースト通知を出す。エントリポイントは `.config/claude/hooks/notify-windows.sh`（`Stop` / `Notification` フックに登録）と `scripts/nippo-cron.sh`。

共通処理は `scripts/lib/` に分けている。

| ファイル                      | 役割                                           |
| ----------------------------- | ---------------------------------------------- |
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

### 日報ファイル自動作成（WSL2専用）

平日8:00に `scripts/nippo-create-cron.sh` が `nippo-add` スキルをヘッドレス実行し、当日の日報ファイルを新規作成する。テンプレート・今日の予定（カレンダー）・前日からの引き継ぎを埋めるので、始業時にはできあがった日報から書き始められる。

**当日ファイルが既にあれば何もしない。** 手動で作った日報を上書きしたり、空の作業ログを追記したりしないため。

```fish
touch ~/.config/nippo-create-enabled
env NIPPO_CREATE_DRY_RUN=1 NIPPO_CREATE_FORCE=1 bash scripts/nippo-create-cron.sh  # 実行内容の確認
crontab -e
# 0 8 * * 1-5 $HOME/scripts/nippo-create-cron.sh >> $HOME/.nippo-create-cron.log 2>&1
```

無効化は `rm ~/.config/nippo-create-enabled`。動作確認は `bash scripts/test-nippo-create-cron.sh`。

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

**`~/Obsidian` は Windows 側の Vault への symlink** で、日報系（`nippo-*`）も含め全スクリプトがこれを既定にしている。新環境ではこの symlink を張る（張らないと出力先が作られてしまい、Obsidian から見えない）。出力先だけ変えたい場合は `ESA_WEEKLY_OUT` で上書きする。

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

### Linear個人司令塔（タスク集約とAI夜間ディスパッチ）

タスクはLinear（team `NSY`）に集約する。**LinearはSoTではなく「ポインタの司令塔」**で、
issueは元URL＋期待アウトカム＋判断状態だけを持つ。本体はJira / GitHub / Slack / esa 側にある。

| やりたいこと        | コマンド                                                  |
| ------------------- | --------------------------------------------------------- |
| 初期設定（ID解決）  | `bash scripts/linear-bootstrap.sh`                        |
| 起票                | `/linear-add`（対話skill。規約を自動適用する）            |
| draft PR→Triage起票 | `bash scripts/linear-sweep.sh`（cron: 平日8:00）          |
| Slackスタンプ起票   | `/linear-slack-sweep`（cron: 平日8:10）                   |
| 起票済みかの確認    | `/linear-recall <スレURL or キーワード>`                  |
| 夜間ディスパッチ    | `bash scripts/linear-dispatch-cron.sh`（cron: 火-土1:00） |
| 動作確認            | `bash scripts/test-linear-api.sh` ほか `test-linear-*.sh` |

**リンクは Linear → 外部の一方向のみ。GitHub / Jira には一切書き戻さない。**
どちらもチームの共有物なので、個人のタスク管理都合のノイズを持ち込まない。

**stateの軸は「今ボールを誰が持っているか」。** `In Progress`（自分が手を動かしている。整理も
ここ）と `My Review`（AIの成果物の判断待ち）の判定は一問で、**「その成果物をAIが作ったか」が
YESのときだけ `My Review`**。自分の作業の確認待ちに専用stateは作らず `In Progress` に持つ。

state一覧と混入の検出、起票規約（Project名のprefix・親子の粒度・ラベルの2軸）、Cycleの設定と根拠、
夜間ディスパッチの2モードと安全弁、Slackスタンプ起票の重複判定は
[docs/linear-command-layer.md](docs/linear-command-layer.md)。

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

### ghq リポジトリへの移動（gf）

`gf` は `ghq list` の結果を `~/.cache/ghq-list` にキャッシュして fzf に流す。パス解決は
`__ghq_list_cache_path`、更新は `__ghq_list_cache_refresh` に分離してある。

**キャッシュ更新は fzf を出す「前」に background で投げる。** 以前は `cd` の後に投げていたが、
fzf を ESC でキャンセルすると `or return` で抜けて更新が走らなかった。そのため
「`ghq get` → `gf` に出ない → ESC → もう一度 `gf`」を繰り返しても永久に反映されず、
一度どこかのリポジトリへ `cd` するまで直らなかった。fzf は先にキャッシュを開いてから読むので、
更新の `mv`（アトミックな rename）が途中で走っても fzf 側は古い inode を読み切る。

**加えて `ghq` 自体を fish 関数でラップし、リポジトリが増減した直後に同期でキャッシュを更新する。**
gf 側の background 更新だけでは「clone 直後の `gf` に間に合う」保証がないため。対象は
`get` / `clone` / `rm` / `create` / `migrate`（ghq 1.10.1 でリポジトリ集合が変わるもの）で、
`list` / `root` などの読み取り系では更新しない。終了ステータスは素通しする。

- **同期更新でよい根拠**: `ghq list` は実測 0.18 秒（43リポジトリ）。これから数秒かかる clone の直後に足す分としては無視できる
- **`--wraps ghq` は付けない。** 関数名と同じで自己参照になるうえ、ghq は fish 補完を同梱していない（`complete | grep ghq` が0件）ので、ラッパー有無で補完に差が出ない
- **`__ghq_list_cache_refresh` の中は `command ghq` で呼ぶ。** ラッパーを経由させず、キャッシュ更新がラッパーの実装に依存しないようにする
- 中間ファイルは `$cache.$fish_pid.tmp`。ラッパーの同期更新と gf の background 更新が同時に走りうるため、固定名だと互いの中間ファイルを踏む
- 更新失敗時はキャッシュを壊さず、stderr を `$cache.err` に上書きして残す（追記だと無限に肥大する）
- テストは `$ghq_list_cache` でキャッシュ位置を差し替えて実キャッシュを避ける

動作確認は `bash scripts/test-gf-cache.sh`。

### git worktree の運用

`git wt` で worktree を作ると `scripts/worktree-init.sh` が走り、gitignore 対象の `.env*` の
コピーと依存インストールを行う。リポジトリ固有の追加初期化を差し込める。

`wt` / `wtd` の fzf 一覧は1列目に由来のタグ（`main` / `.wt` / `claude` / `wt`）を出す。

| やりたいこと          | コマンド                                             |
| --------------------- | ---------------------------------------------------- |
| 候補の確認（dry-run） | `bash scripts/worktree-cleanup.sh`                   |
| 解放見込みつきで確認  | `bash scripts/worktree-cleanup.sh --size`            |
| 実削除                | `bash scripts/worktree-cleanup.sh --execute`         |
| 追跡ファイルごと削除  | `bash scripts/worktree-cleanup.sh --execute --force` |

**掃除は既定が dry-run** で、実削除には `--execute` が要る。判定は上から順に評価し、
`locked` を最優先で SKIP する（Claude Code の worktree はセッション実行中に lock されるため、
これを PR 状態より先に見ないと作業中のディレクトリを消す）。

初期化のリポジトリ別カスタム、タグ判定の根拠、掃除の判定表と「未追跡ファイルを dirty 扱いしない」
理由は [docs/worktree.md](docs/worktree.md)。

### セッションの復元（herdr / `he`）

reboot 後に `he` を叩くと、レイアウトだけでなく **nvim と claude のプロセスまで**復活する。
以前は tmux の continuum + resurrect（`@resurrect-processes`）でやっていたが、herdr へ移行した際に
撤去し、同等の仕組みを herdr 上に作り直している。

| 何を                                     | 誰が復元するか                    |
| ---------------------------------------- | --------------------------------- |
| レイアウト / タブ名 / ペイン label / cwd | herdr の `session.json`（native） |
| nvim / claude のプロセス                 | `scripts/herdr-restore.sh`        |
| nvim のバッファ                          | auto-session（**ペイン単位**）    |

**herdr は前面プロセスを保存しない。** そのため各プロセスが自分でマーカーを残す方式にしている。

| プロセス | マーカー                                | 書く場所                                      |
| -------- | --------------------------------------- | --------------------------------------------- |
| nvim     | `~/.local/state/herdr-nvim/<pane_id>`   | `.config/nvim/lua/my/settings/autocmd.lua`    |
| claude   | `~/.local/state/herdr-claude/<pane_id>` | `.config/claude/hooks/herdr-claude-marker.sh` |

- **一斉起動しない。** 種別ごとに同時投入数と間隔を絞る（nvim は3個ずつ2秒間隔、claude は1個ずつ8秒間隔）。
  reboot 直後に数十個の nvim と claude が同時に立ち上がると負荷スパイクで固まるため。
  `HERDR_RESTORE_NVIM_BATCH` 等で調整できる
- **`he` も `herdr-restore.sh` も flock で多重起動を防ぐ。** 複数端末から同時に `he` を叩いても
  サーバー起動は1プロセスだけが行う
- 何がどの順で流れるかは `bash scripts/herdr-restore.sh --dry-run` で確認できる
- **claude の cwd はマーカーから戻す。** herdr の `session.json` が持つペインの cwd はシェルのもので、
  claude がセッション中に worktree へ移った分は残らない。マーカーの cwd が実在するときだけ
  `cd <cwd> && claude --resume <id>` に組み立てる（worktree が消えていても claude 自体は立てる）
- **`SessionEnd` は自分が書いたマーカーだけ消す。** worktree に入ると session_id が変わるので、
  無条件に消すと新セッションのマーカーを旧セッションの end が持っていき、そのペインが復元されない
- **nvim のセッションはペイン単位で分かれる。** cwd 単位だと、同じリポジトリを2ペインで開いていたときに
  片方のバッファでもう片方が上書きされる
- **ペイン単位のセッションが無ければ cwd 単位のセッションへ落ちる。** タグ付けの目的は複数ペインの
  上書き防止なので、読み込み側まで厳格にする必要はない。落ちた後の保存はペイン単位の名前で行われるため、
  1回開けば自動で移行する（この後付けが無かったため、タグ導入直後の reboot で全ペインが空で起動した）
- **フォールバックは引数なしの起動だけで働く。** auto-session の `no_restore` フックは
  「タグ付きが無かった」以外の理由でも発火する。`nvim somefile` は
  `args_allow_files_auto_save = false` により復元対象外だがフックは発火するため、絞らないと
  指定したファイルがセッションの内容に置き換わる（実際にこれで別ファイルが開く事故が起きた）。
  同じ理由で headless（`nvim --headless "+Lazy! sync"`）と pager モードも除く
- **スクラッチパッドが画面に出ている間はセッションを保存しない。** `~/.inbox.md`（`:Inbox`）と
  `~/.nvim_tmp/` 配下（`:Temp`）は全プロジェクト共有なので、プロジェクト固有のセッションの
  表示バッファになるとフォールバック経由で同じ cwd の全ペインへ広がり、定期保存で焼き付く
  （実際に9本のセッションが `~/.inbox.md` で埋まった）

#### 復元の進み具合を見る

投入は数分に散るので、走っているのか終わったのかを外から見えるようにしている。

| やりたいこと            | コマンド                                  |
| ----------------------- | ----------------------------------------- |
| 進み具合の確認          | `he --status`                             |
| 投入順の確認（dry-run） | `bash scripts/herdr-restore.sh --dry-run` |

```
herdr 復元: 実行中  nvim 4/10, claude 0/5  経過 1分23秒
herdr 復元: 完了  nvim 10/10, claude 4/5 (1件は使用中でスキップ)  所要 3分18秒
herdr 復元: 中断  nvim 4/10, claude 0/5  開始から 1分23秒 (プロセス不在)
```

- 状態は `~/.local/state/herdr-restore.status` に key=value で持つ。書き込みは tmp + `mv` で行い、
  読み手が書きかけの行を読まないようにする
- **`--status` はロックより手前で処理する。** 復元中は flock が取れず、黙って終わってしまうため
- **ペインが使用中で触らなかった分は skipped として数える。** done と total が食い違う理由が
  表示だけでわかるようにするため
- **`state=running` のまま pid が居なければ「中断」。** 復元プロセスが落ちたことに気づけるようにする
- 開始と完了は Windowsトースト通知でも出す。**復元対象が0件なら状態ファイルも通知も触らない**
  （既にサーバーが動いている状態の `he` でトーストが飛ぶのを避けるため）
- **通知の完了は待たない。** `Import-Module BurntToast` に実測10秒前後かかり、reboot 直後は
  さらに伸びる。復元キューの頭とお尻をそれで止めるのは割に合わないので、`timeout` を付けて投げっぱなしにする

設計の経緯は [docs/session-restore-strategy.md](docs/session-restore-strategy.md)。動作確認は `test-herdr-restore.sh` /
`test-herdr-claude-marker.sh` / `test-herdr-nvim-session-tag.sh` / `test-nvim-session-autosave.sh`。
**後ろ2本は CI では走らない**（実 nvim 設定と auto-session の導入済み環境が要るため `# ci-skip:` 宣言済み）。

### Docker開発

- `find_docker_compose` 関数でcomposeファイルを自動検出
- 略語: `dc` (docker compose), `dcl` (logs), `dcu` (up), `dcd` (down)
- 複数のcomposeファイルの場所と命名パターンをサポート

### Docker の掃除

`dclean`（fish関数）で不要な Docker リソースを掃除する。fish起動時に溜まり具合を1行で通知する。

| やりたいこと | コマンド                                                                     |
| ------------ | ---------------------------------------------------------------------------- |
| 現状確認のみ | `dclean --status`                                                            |
| 軽掃除       | `dclean`（停止コンテナ / dangling image / 匿名volume / 未使用のbuild cache） |
| 重掃除       | `dclean -a`（軽 + 未使用image全部 + 共有ぶんも含むbuild cache全部）          |
| 使い方       | `dclean --help`                                                              |
| 動作確認     | `bash scripts/test-docker-clean.sh`                                          |

- **named volume は軽・重どちらでも削除しない**（未使用でも DBデータ等は残す）
- **稼働中コンテナも停止しない。** 閾値超過を一覧表示するだけで、停止は手動判断

種別タグ（compose / orphan / standalone）の判定順、build cache を全ビルダー対象にする理由、
`--filter until=` を使わない実測根拠、通知の閾値と環境変数は
[docs/docker-clean.md](docs/docker-clean.md)。

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

## 社内固有情報を入れない運用

**このリポジトリは public。** 社名・社内ホスト名・社内リポジトリ名・Jiraプロジェクトキー・
案件コード・顧客略号を入れない。

置き場所は次のとおり。**リポジトリにあるのはプレースホルダ入りの `.example` だけ**で、
値の実体は必ずリポジトリ外か gitignore 対象に置く。

| 何を                                                                                   | どこに置くか                                                             | 雛形                                      |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ----------------------------------------- |
| Jira cloudId・プロジェクトキー・GitLabホスト・esaチーム名・リポジトリ名・案件/顧客略号 | `~/.claude/local-context.md`                                             | `.config/claude/local-context.md.example` |
| 機密語辞書                                                                             | `~/.config/dotfiles/secret-patterns.txt`                                 | `scripts/secret-patterns.txt.example`     |
| nvim の HTTPS 非対応ホスト                                                             | `my/local_config.lua`                                                    | `my/local_config.lua.example`             |
| dclean の除外パターン                                                                  | `99-local.fish`                                                          | −                                         |
| 社内向けAHKスニペット                                                                  | `snippets-local.ahk` と `ahk-snippets/js/`                               | −                                         |
| 社内プラグインの有効化と marketplace 定義                                              | 実ファイルのみ。`sync-claude-settings.sh` がマスクする                   | −                                         |
| 社内システム名で発動する skill                                                         | `.config/claude/skills/cross-repo-auto-discover/` ごと ignore            | −                                         |
| 例示・テストデータ                                                                     | `example-org` / `example-repo` / `CUST-A` などの架空名でコミットしてよい | −                                         |

**辞書と `local-context.md` をリポジトリに置かないのが要点。** どちらも中身が機密そのもので、
コミットすると分離した意味が消える。

検査は2層。`scripts/secret-scan.sh` が両方の実体で、`--staged` と `--tree` の2モードを持つ。

| 層                                                | いつ          | 辞書                           |
| ------------------------------------------------- | ------------- | ------------------------------ |
| pre-commit hook（`core.hooksPath=scripts/hooks`） | commit の手前 | 実体（社内語を含む）           |
| GitHub Actions（`secret-scan.yml`）               | push / PR     | `.example`（汎用パターンのみ） |

- **CI は辞書の実体を持てない**（public リポジトリなので Actions のログも公開される）。
  主の防壁は hook 側で、CI は push 後の最終防波堤
- **辞書が無い環境では警告して通す。** 新環境で `dotfilesLink.sh` を走らせる前に
  commit できなくなるのを避けるため。`dotfilesLink.sh` が `.example` から雛形を作る
- **パス名も検査する。** ファイル名に社内システム名が入っていると、中身を置換しても残るため
- **`.gitignore` に書く行自体が漏洩源になりうる。** ファイル名に社内名が入る場合は
  ディレクトリ単位で ignore する
- `--no-verify` は原則使わない

動作確認は `bash scripts/test-secret-scan.sh`。

## 重要な注意事項

- 一部の設定ファイルで日本語コメントを使用
- Windows Docker統合によるWSL2環境サポート
- 企業環境用Zscaler証明書設定
- Fish shellでtideプロンプトテーマ（コピー＆ペーストの利便性のため右プロンプトは無効）
