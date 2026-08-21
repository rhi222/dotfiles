# AGENTS.md

## リポジトリ概要

各種開発ツールやアプリケーションの設定ファイルを含む個人用dotfilesリポジトリです。シンボリックリンクを使用して、異なるシステム間で設定ファイルを管理しています。

**このファイルは全機能の「何ができるか」と、判断に効く要点を持つ。**
このファイルは毎セッションのコンテキストに丸ごと載るので、**各機能の表（やりたいこと →
コマンド）と、選択を左右する数個の理由だけを置く**。細かい根拠・実測値・失敗の記録は
`docs/` に分けてある。**必要になったときに開けばよく、先に全部読む必要はない。**

| 文書                                                                 | いつ開くか                                           |
| -------------------------------------------------------------------- | ---------------------------------------------------- |
| [docs/bootstrap.md](docs/bootstrap.md)                               | 新しい端末を立ち上げるとき。機密ファイルの台帳もここ |
| [docs/migration.md](docs/migration.md)                               | PC 移行でリポジトリ群と作業状態を運ぶとき            |
| [docs/claude-skills.md](docs/claude-skills.md)                       | skill の信頼境界・vendoring の判断を変えるとき       |
| [docs/linear-command-layer.md](docs/linear-command-layer.md)         | Linear の起票規約・Cycle・夜間ディスパッチを触るとき |
| [docs/worktree.md](docs/worktree.md)                                 | worktree の初期化・掃除の判定を変えるとき            |
| [docs/git-worktree-tool.md](docs/git-worktree-tool.md)               | `git wt` サブコマンド自体の使い方を調べるとき        |
| [docs/session-restore-strategy.md](docs/session-restore-strategy.md) | `he` の復元（herdr / nvim / claude）を触るとき       |
| [docs/herdr-ui.md](docs/herdr-ui.md)                                 | herdr のタブ行ステータスや keybinding を変えるとき   |
| [docs/notifications.md](docs/notifications.md)                       | トースト通知の内容や抑止の条件を変えるとき           |
| [docs/docker-clean.md](docs/docker-clean.md)                         | `dclean` の判定や閾値を変えるとき                    |
| [docs/scripts-layout.md](docs/scripts-layout.md)                     | scripts/ の入口・参照・テストの構成を触るとき        |

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

確認は次の4つ。

```fish
bash scripts/lint.sh                # shellcheck + shfmt（追跡＋未追跡の全 .sh）
bash scripts/secret-scan.sh --tree  # 機密語スキャン（辞書を埋めた後に）
bash scripts/run-tests.sh           # 全テスト（並列。TEST_JOBS=1 で直列）
bash scripts/doc-budget.sh          # AGENTS.md の行数予算
bash scripts/ref-check.sh           # scripts/ 配下への参照が壊れていないか
```

`run-tests.sh` は並列で走るが**出力は直列時と同じ**。前提は各テストが `mktemp` で
自分の作業場を作ること。`ref-check.sh` は散文からの参照先の実在を検査する
（pre-commit と CI の二層）。詳細は [docs/scripts-layout.md](docs/scripts-layout.md)。

### ローカル設定の集約と移植（private bundle）

gitignore しているローカル設定・機密ファイルは `~/.local/share/dotfiles-private/` に集約する。
**実体は集約先にあり、各所へは `dotfilesLink.sh` が symlink を張る。** 以前はリポジトリ作業ツリー内・
ホーム直下・XDG 配下の3箇所に散っていて、新環境で12項目を手で配り直す必要があった。

| やりたいこと        | コマンド                                         |
| ------------------- | ------------------------------------------------ |
| 集約（旧環境で1回） | `bash scripts/private-bundle.sh adopt --execute` |
| 運搬用に固める      | `bash scripts/private-bundle.sh export`          |
| 新環境で展開        | `bash scripts/private-bundle.sh import <zip>`    |
| 状態の確認          | `bash scripts/private-bundle.sh status`          |
| 動作確認            | `bash scripts/test-private-bundle.sh`            |

- **リンク規則は1つだけ。** リンク先が実ディレクトリなら1階層降り、無ければそこでリンクする。
  これでファイル単位（`config-local`）とディレクトリ単位（`ahk-snippets/js`）が自動で振り分けられ、
  マニフェストを持たずに済む。**ローカル設定を足すときは集約先に置くだけでよく、
  `dotfilesLink.sh` は変わらない**
- **ファイル単位で張りたいのに親が新環境に無いものは `ensure_dirs` で先に作る。**
  `~/.config/linear` がそれで、作らないとディレクトリごとリンクされ、`linear-bootstrap.sh` が書く
  `config.json`（再生成できる）まで zip に混ざる
- **`export` の `zip -y` は必須。** 集約先の中の `cross-repo-auto-discover/repos.yml` は相対 symlink で、
  辿って実体化すると `repos.yml` が2つになる。**実体化しても「中身が読める」テストは通ってしまう**ので、
  symlink であること自体を検査する回帰テストを置いている
- **`import` はパーミッションを張り直す。** zip の保存内容に頼ると、Windows 側で開いて再圧縮された
  場合に `api-key` が 644 で復元される
- **リンク先に実ファイルがあれば退避する。** `ln -snf` は黙って消すので、`import` より先に
  `config-local` を手書きした端末で内容が失われる
- **`adopt` の既定は dry-run。** 旧環境で1回だけ走らせる移行コマンドなので、`--execute` を要求する
- **集約先が無ければ従来どおり `.example` からの雛形生成にフォールバックする。**
  旧環境が無い立ち上げの挙動は変えていない
- 対象外: `~/.claude/settings.json`（`sync-claude-settings.sh` の担当）、
  `.config/codex/config.toml`（雛形生成のまま）

移植対象の一覧は `private-bundle.sh` の `ADOPT_ENTRIES`。**パスに社内名を含むものは既に
`.gitignore` に書かれている**ため、public リポジトリに一覧を置いても新たな漏洩は起きない。
`passwords/` だけは `@under` 指定で、直下のうち git が ignore しているものを拾う
（`README.md` が追跡対象で、子の名前は端末ごとに違いうるため）。

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

### Windows 側設定の同期（.wslconfig / Windows Terminal）

`/mnt/c` にあって symlink できない設定を `scripts/sync-windows-settings.sh` でコピー同期する。
`sync-claude-settings.sh` と同じく**実ファイルを正とし、リポジトリが追いかける**。

| リポジトリ                               | 実ファイル                                     |
| ---------------------------------------- | ---------------------------------------------- |
| `.config/wsl/.wslconfig`                 | `%USERPROFILE%\.wslconfig`                     |
| `.config/windows-terminal/settings.json` | Windows Terminal の `LocalState/settings.json` |

| やりたいこと            | コマンド                                             |
| ----------------------- | ---------------------------------------------------- |
| 差分の確認              | `bash scripts/sync-windows-settings.sh status`       |
| 実ファイル → リポジトリ | `bash scripts/sync-windows-settings.sh pull`         |
| リポジトリ → 実ファイル | `bash scripts/sync-windows-settings.sh push --force` |
| 片方だけ                | 末尾に `wslconfig` / `terminal` を付ける             |

- **symlink にできない理由が2つある。** ①実体が NTFS 上にあり、WSL から張った symlink を
  Windows 側が解釈しない ②Windows Terminal は distro を検出するとプロファイルを
  `settings.json` へ自動追記する（`~/.claude/settings.json` と同じ書き戻し問題）
- **`dotfilesLink.sh` からは呼ばない。** `.wslconfig` の `memory` は「その端末の物理RAMと
  Windows 側の使用量」から出した実測値で、別スペックの端末へ自動で配ると不適切になる。
  新環境では [docs/bootstrap.md](docs/bootstrap.md) の手順として人間が判断して押し出す
- **正規化は Terminal 側だけ `jq -S`。** `.wslconfig` は INI なので素通しする。
  JSON バリデータに掛けると通らないうえ、**値の導出過程を書いたコメントが消える**
- **壊れた内容は反対側へ伝播させない。** Windows Terminal の `settings.json` は JSONC を
  許容するので、コメントを書くと `jq` が失敗して同期が止まる（現物はコメント無し）
- プロファイルの GUID は distro 名から決定的に生成されるため、同じ distro 名なら別端末でも一致する

動作確認は `bash scripts/test-sync-windows-settings.sh`。

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

### 環境の残骸チェック（env-residue.sh）

**宣言のどこにも属さないのに環境に居座っているもの**を洗い出す。
`daily-update.sh` が `run_step_soft` で毎日呼ぶ（情報提供なので FAILED にしない）。

```fish
bash scripts/env-residue.sh
```

| 何を見るか                                  | なぜ                                                       |
| ------------------------------------------- | ---------------------------------------------------------- |
| `~/.fzf/` と `~/.fzf.bash`                  | mise 管理と二重。PATH 順で古い版を掴む端末が出る           |
| `~/.config/fish/functions/` の追跡外ファイル | Ctrl+R の担当が端末ごとに割れる原因になる                  |
| `~/.claude` `~/.codex` `~/.agents` の skill | 宣言に無いもの、vendored なのに実ディレクトリになったもの   |

- **既存のどのチェックにも掛からない種類の drift を埋めるためのもの。**
  `migration-check.sh` は「リポジトリの作業状態」専用で環境は見ない。
  実際にこの3種類を全部踏んだ（追跡外の `fish_user_key_bindings.fish` で Ctrl+R の
  修正が端末をまたぐたび戻り、vendored skill 6本が古い gh 版に隠されていた）
- **fisher の判定は名前の規約ではなく fisher 自身が持つ一覧で行う。** fisher は
  プラグインごとに universal 変数 `_fisher_<plugin>_files` へインストールした
  ファイルを記録している。「`_` 始まりはプラグイン」で切った初版は tide の
  `fish_prompt` / `fish_mode_prompt` / `tide`、`fisher` 本体、fzf.fish の
  `fzf_configure_bindings` を**誤検知した（実環境で5件）**。公開関数は普通の名前を持つ
- **skill の宣言が読めないときは skill の判定を丸ごと諦める。** 読めないまま
  「宣言に無い」と言うと、正しく入っているものまで残骸に見える
- **見つかっても exit 0。** 残骸があること自体は壊れている状態ではなく、放置すると
  事故になりうる状態。毎日 FAILED が飛ぶと無視されるようになる
- 件数は機械可読サマリ行（`env-residue: FOUND=N`）から取る。表示の体裁を変えても
  呼び出し側が壊れないようにするため（`worktree-cleanup.sh` と同じ作り）

動作確認は `bash scripts/test-env-residue.sh`。

### 日次アップデート（daily-update.sh）

`scripts/daily-update.sh` が各パッケージマネージャとツールの更新をまとめて回す。
apt / cargo / mise（self-update・upgrade・prune）/ npm global / pip global /
nvim の Lazy と Mason / gh skill / gh extension / yazi プラグイン / fisher の順に実行し、
最後に worktree の溜まり込み・vendored skill の更新・環境の残骸のチェックと
`sync-claude-settings.sh pull` を行う。

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

### Claude Code skill管理（信頼境界と vendoring）

外部 skill は**提供元で2つの導線に分ける**。`skill` は指示なので、更新は
「依存パッケージの更新」ではなく「エージェントへの指示の更新」にあたる。

| 導線     | 対象                                | 実体                                                            | 更新                                          |
| -------- | ----------------------------------- | --------------------------------------------------------------- | --------------------------------------------- |
| trusted  | `trusted-skill-owners.txt` の owner | `~/.claude/skills/<name>`（gh が入れた実ディレクトリ）          | `daily-update.sh` の `gh skill update --all`  |
| vendored | それ以外すべて                      | `.config/claude/skills-vendor/<name>/`（コミット済み）→ symlink | 検知のみ自動。取込は手動 + audit + `git diff` |
| 自作     | 自分                                | `.config/claude/skills/<name>/`                                 | 該当なし                                      |

| やりたいこと           | コマンド                                                                 |
| ---------------------- | ------------------------------------------------------------------------ |
| trusted な skill 追加  | `bash scripts/skill-add.sh <owner/repo> <skill>`                         |
| vendored な skill 追加 | `bash scripts/skill-vendor.sh add <owner/repo> <sub-path> [name]`        |
| vendored の更新        | `bash scripts/skill-vendor.sh update <name>`                             |
| vendored の点検        | `bash scripts/skill-vendor.sh status` / `list`                           |
| 単体で内容を検査       | `bash scripts/skill-audit.sh <skill-dir>`                                |
| 新環境 bootstrap       | `env STRICT=1 bash scripts/setup-claude-skills.sh` + `./dotfilesLink.sh` |
| 削除（vendored）       | `rm -rf .config/claude/skills-vendor/<name>` + `./dotfilesLink.sh`       |

**allowlist は default-deny。** 初期値は `anthropics` / `github` / `vercel-labs` の3つだけで、
**個人アカウントは入れない**（allowlist に入れることは「人のレビューなしで毎日自動更新される」
ことと同義）。allowlist 外の owner を渡すと `skill-add.sh` と `setup-claude-skills.sh` の
**両方**がエラーで止まり、vendor 導線が案内される。

**vendored はリポジトリにコミットする。** 更新のレビュー面を `git diff` に一本化するため。
`.vendor.json` が唯一の正で、`ls skills-vendor/` が一覧そのもの（中央の一覧ファイルは持たない）。

**未検証の skill を Claude に読ませない。** レビューの主体は人に置く。読ませた時点で
ペイロードが会話コンテキストに入るので、`skill-audit.sh` はプロンプトを一切生成せず、
audit が0件でも人の承認を要求する。

fail-closed の倒し方、`reviewed_commit` と live-dir の検査、`lint.sh` / `secret-scan.sh` の
扱い、`local:` 行を廃止した理由は [docs/claude-skills.md](docs/claude-skills.md)。
動作確認は `bash scripts/test-skill-audit.sh` / `test-skill-vendor.sh` /
`test-claude-skills-allowlist.sh`。

### Codex自作skill管理

Codex専用の自作skillは `.config/codex/skills/` に置く。`dotfilesLink.sh` が、Codexの
ユーザー共通探索先 `~/.agents/skills/` へskill単位でsymlinkを張る。リポジトリ内の
`.agents/skills/` に直接置くとこのdotfilesリポジトリでしか有効にならず、PR作業など他の
リポジトリで使うskillを共有できないため、実体と探索先を分けている。

- 外部skillと同居できるよう、`~/.agents/skills` 全体はリンクしない
- セットアップ時に刈るのはリンク切れのsymlinkだけで、外部skillの実ディレクトリには触れない
- skill追加後は `./dotfilesLink.sh` を実行する。Codexが変更を検出しない場合は再起動する
- PR説明文の整理には `refine-pr-description` を使う。本文案の提示が既定で、明示依頼なしに
  PR本文を更新しない

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

### fish プラグイン管理（fisher）

fish のプラグインは fisher で管理し、宣言リストは `.config/fish/fish_plugins`
（`dotfilesLink.sh` がリンクする）。中身は tide（プロンプト）と fzf.fish（Ctrl+R / Ctrl+T）。

| やりたいこと     | コマンド                                                     |
| ---------------- | ------------------------------------------------------------ |
| プラグイン追加   | `fish_plugins` に追記 → `bash scripts/setup-fish-plugins.sh` |
| 一括インストール | `bash scripts/setup-fish-plugins.sh`（揃っていればskip）     |
| 新環境 bootstrap | `env STRICT=1 bash scripts/setup-fish-plugins.sh`            |
| 更新             | `daily-update.sh` が `fisher update` を実行                  |
| 削除             | `fish_plugins` の行削除 → `setup-fish-plugins.sh`            |

- **以前は追跡外だった。** そのため端末ごとにプラグイン集合が割れ、`daily-update.sh` にも
  更新ステップが無く、tide と fzf.fish だけどの端末でも手動更新だった。
  **Ctrl+R の時刻列を消す修正が端末をまたぐたび元へ戻った**のはこれが根にある
  （担当が fzf.fish か fzf 標準統合かで読む変数が変わる。`.config/fish/README.md`）
- **symlink にできる。** fisher の書き戻しは `printf ... > $fish_plugins` で symlink を
  貫通する。`~/.claude/settings.json` のような tmp + rename ではないのでリンクが外れない
  （実体を消すのは全プラグインを remove したときだけ）
- **`fisher update` は未宣言のものを削除する。** 宣言と実体を突き合わせる完全な reconcile
  なので、`ya pkg install` より強い。その端末だけで手動 install したものは消えるため、
  `setup-fish-plugins.sh` は**消える対象を事前に名指しで出す**
- **`ln -snf` の前に実ファイルを退避する。** 宣言リストは「その端末に何が入っているか」の
  唯一の記録なので、黙って消すと別端末の宣言が失われる。**内容が同じなら退避しない**
  （両端末とも同じ3つという通常ケースで無意味な `.bak` を増やさない）
- **`dotfilesLink.sh` からは自動実行しない。** 無ければプロンプトが既定に戻り Ctrl+R が
  fish 標準の history-pager になるだけで、yazi のように**起動そのものが失敗はしない**。
  gh 拡張と同じ「無ければ機能が欠けるだけ」の側
- **fisher の終了コードだけを信じない。** 緑で返っても実体が入っていなければ失敗として扱う
  （yazi と同じ判断。プロンプトと Ctrl+R が黙って死ぬ状態を作らない）
- tide の見た目は156個の universal 変数で決まり `fish_variables` は追跡外なので、
  宣言には含められない。bootstrap の `tide configure --auto` が担当

動作確認は `bash scripts/test-fish-plugins.sh`。

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

通知は2種類。**完了通知**（Stopフック）はタイトルにリポジトリ名とブランチ、本文に
トランスクリプトから抽出した最後のアシスタント発言を出す。**日報リマインド通知**は
平日の業務時間中に日報の状態を報告する。

```
✅ dotfiles (main)
テストを追加してlintも通りました。コミット済みです。
```

- **`stop` と `cron` で報告内容を変える。** `stop` は応答が終わるたびに発火するので、
  一日中真になり続けるチェック（90分以上未更新・未完了タスク数）は cron 専用にしている
- **Stop フック側は二段のゲートを掛ける。** 実行ゲート（10分に1回。日報は `/mnt/c` (9p) 上に
  あり1ファイル操作あたり数秒かかる）と通知クールダウン（同一内容は60分に1回）。
  状態は `~/.cache/claude-nippo-notify/{last-run,last-notify}`。**通知が来なくなったと
  思ったらこの2ファイルを消せばリセットされる**

日報リマインドの有効化:

```fish
touch ~/.config/nippo-notify-enabled
crontab -e
# 0 9,11,13,15,17,19 * * 1-5 $HOME/scripts/nippo-cron.sh >> $HOME/.nippo-cron.log 2>&1
```

無効化は `rm ~/.config/nippo-notify-enabled`。チェック項目の対応表と本文の組み立ては
[docs/notifications.md](docs/notifications.md)。動作確認は `scripts/test-nippo-check.sh` /
`test-notify-cooldown.sh` / `test-stop-notification.sh`。

### 日報の置き場とパス解決

日報は `~/Obsidian/02_Daily/` に置き、**種別 + 年/月**で構造化している。

| パス                                   | 中身     |
| -------------------------------------- | -------- |
| `daily/YYYY/MM/nippo.YYYY-MM-DD.md`    | 日次     |
| `weekly/YYYY/nippo-weekly.YYYY-Wnn.md` | 週次     |
| `config/nippo-goals.md`                | 目標設定 |

**パス解決は `scripts/lib/nippo-paths.sh` に集約している。skill もスクリプトも
パスを直接組み立てない。** 以前は11 skill + 3 script がそれぞれ
`$HOME/Obsidian/02_Daily/nippo.${DATE}.md` を組み立てており、ディレクトリ構造を
変えられない原因になっていた。

- 環境変数は `NIPPO_VAULT`（`~/Obsidian`）と `NIPPO_DIR`（`~/Obsidian/02_Daily`）の2系統。
  どちらも既存のもので、新しい名前は増やしていない。`NIPPO_DIR` が優先される
- **既定値を変数に焼き込まない。** `~/Obsidian` は Windows 側 Vault への symlink で、
  テストが `$HOME` を差し替えて追随を検査するため、関数が呼ばれるたびに評価する
- **cron の `--allowedTools` に `Bash(source:*)` / `Bash(ghq:*)` が要る。**
  cron は skill の frontmatter とは別に許可リストを自前で持っており、
  ここを忘れると skill がライブラリを読めず自動実行が権限で落ちる
- **テストもレイアウトを直書きしない。** `test-nippo-check.sh` はフィクスチャの置き場を
  直書きしていて、フラット→年/月の移行で本体と食い違って落ちた。いまは
  `nippo_daily_file` / `nippo_daily_dir` に解決させている
- **`ls` のグロブでは日報を数えない。** 階層が変わると効かなくなるので `find` を使う
  （`nippo-show` の過去一覧がこれ）
- ファイル名は階層に依存しない。`nippo.YYYY-MM-DD.md` だけで一意に特定でき、
  Obsidian の switcher・全文検索・fzf はそのまま使える
- 週次は月境界をまたぐので月では畳まない。年32件なので年だけで足りる

skill は6本（`nippo-add` / `nippo-finalize` / `nippo-weekly` / `nippo-reflect` /
`nippo-show` / `nippo-brief`）。**振り返り系は `nippo-reflect` 1本に統合していて、
モード引数は持たない。** 以前は reflection / insight / guide の3本に分かれていたが、
142日分の日報で出力痕跡が計7ファイルしかなかった。`finalize` の直後に「どれを呼ぶか」を
毎回決めさせられるのが原因なので、分岐を残すと同じ判断コストが戻る。

動作確認は `bash scripts/test-nippo-paths.sh`。

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

### 面談準備の自動起票

日報の新規作成時に、**当日と翌営業日**の予定から面談・面接を拾い、準備タスクを Linear の
`Todo` へ自動起票する。日報側にも `## 面談準備` セクションが入る。
判断（どれが面談か・準備に何が要るか）は `nippo-add` skill の `interview-prep.md`、
状態変更は `scripts/linear-interview-prep.sh` が持つ（`linear-slack-sweep` と同じ役割分担）。

- **重複防止が設計の中心。** 当日分と翌日分で**同じ予定を必ず2回拾う**ので、防げないと
  毎朝二重に起票される。キーは Google Calendar の event id（日時やタイトルと違って不変）で、
  ①`~/.local/state/linear-interview-prep/seen.txt` ②Linear を event id で全文検索、の2層で防ぐ。
  ②があるのは seen を消した端末・新環境のため
- **既存が見つかってもコメントしない。** `linear-slack-sweep` はスレの「再燃」を拾うので
  追記に意味があるが、こちらは同じ予定を2回見ているだけで新しい事実が無い。
  付けると毎朝コメントが増えて issue が読めなくなる
- **`Triage` ではなく `Todo` に入れる。** Triage は「やるべきか判断する」箱だが、面談は
  カレンダーで確定済みで判断の余地が無い。ここだけスイープ起票の規約から外している
- **判定キーワードは `面談` / `面接` の2語だけ。** 実データではカジュアル面談・オファー面談・
  採用チャネル経由・業務委託・社内の配属面談が全てこのどちらかを含む。チャネル名や社名で
  条件を足すと名前が変わるたびに漏れるうえ、public リポジトリに社内固有の語を置けない
- **`1on1` は対象外。** 定例で毎週あり、毎週積まれると Linear が汚れる
- **`nippo-create-cron.sh` の `ALLOWED_TOOLS` に `Bash(bash:*)` が要る。** cron は skill の
  frontmatter とは別に許可リストを自前で持つので、忘れると手動では動くのに 8:00 の
  自動実行だけ権限で落ちる
- 候補者の実名・メール・スキルシートURLは**日報（ローカル）と Linear にだけ**入る。
  リポジトリ側の skill 本文とテストには架空名しか置かない

動作確認は `bash scripts/test-linear-interview-prep.sh`。

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
| Slackスタンプ起票   | `/linear-slack-sweep`（cron: 平日10:10）                  |
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
    ├── 00-paths.fish           # PATH設定（mise より前に読ませる）
    ├── 01-mise.fish            # mise（ランタイム管理）
    ├── 02-history.fish         # 履歴設定
    ├── 03-environment.fish     # 環境変数
    ├── 05-tide-settings.fish   # tideプロンプト設定
    ├── 06-aliases.fish         # エイリアス
    ├── 07-abbr.fish            # 略語
    ├── 08-prompt-override.fish # カスタムプロンプト（tide拡張）
    ├── 09-git-wt.fish          # Git worktree
    ├── 10-fzf.fish             # fzf設定
    ├── 11-yazi.fish            # yazi連携（cdキーバインド等）
    ├── 12-herdr.fish           # herdr起動ラッパー（he）
    ├── 13-docker-clean.fish    # docker掃除のリマインド
    └── 14-linear-sweep.fish    # Linearスイープの取りこぼし補完
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

### PR base のガード（Claude Code hook）

`.config/claude/hooks/pr-base-guard.sh` が `PreToolUse`（matcher `Bash`）で走り、
`gh pr create --base <既定ブランチ以外>` を検出したら `permissionDecision: ask` で割り込む。

**散文の規約が守られなかったので機械化した。** stacked PR は `gh-stack` を使うという規約は
`rules/pull-request.md` の「ツール」節と `wt-pr/SKILL.md` の両方に書いてあるが、どちらも
**宣言文であって手が動く瞬間のチェックではない**。規約を読む時点と `gh pr create` を打つ時点の
間に実装・コミット分割・push が挟まるため、この距離があるかぎり確率的に取りこぼす（実際に
`git switch -c` → `gh pr create --base <下のブランチ>` を手作業で組んだ事故が起きている）。
stacked かどうかが確定する唯一の瞬間が base の指定なので、そこにゲートを置く。

- **`deny` ではなく `ask`。** `backport-pr` skill は正当に非デフォルト base の PR を作るので
  deny だと詰まる。ask なら理由文が人間とモデルの両方に見え、判断を人間に戻せる
- **既定ブランチはローカルだけで解決する。** `refs/remotes/origin/HEAD` →
  `init.defaultBranch` → `main` の順。PR 作成のたびに走るのでネットワークに出ない
- **全面的に素通しへ倒す。** jq 不在・壊れた JSON・git リポジトリ外・`--base` 無しは黙って通す。
  hook が PR 作成を壊すほうが、規約の取りこぼしより害が大きい
- **`gh stack` 自身は引っかからない。** 一致条件を `gh pr create` に絞ってあり、`gh pr list --base`
  や `git rebase --base` も対象外
- `git switch -c` は見ない。ブランチを切る時点では stacked かどうか決まっておらず誤検知しか生まない
- 登録先は `settings.json` なので、変更後は `sync-claude-settings.sh` で同期し、Claude Code を再起動する

動作確認は `bash scripts/test-pr-base-guard.sh`。

### 行数予算の検査（doc-budget）

**このファイル自身が肥大するのを機械的に止める。** 冒頭で「表と数個の理由だけを置く」と
宣言しているのに 4月の 6KB から 8月に 66KB まで増え、圧縮を2回やって2回とも数日で戻った。
宣言は commit の瞬間のチェックではないので、そこにゲートを置く（`pr-base-guard` と同じ倒し方）。

| やりたいこと | コマンド                             |
| ------------ | ------------------------------------ |
| 検査         | `bash scripts/doc-budget.sh`         |
| 予算の変更   | `scripts/doc-budget.txt` を編集      |
| 動作確認     | `bash scripts/test-doc-budget.sh`    |

- **予算は「ファイル全体」と「1セクション」の二段。** 全体だけだと肥大した1節を見逃し、
  セクション上限だけではファイルが縮まない（900行に対し、20行上限でも削減見込みは231行。
  巨大な数節ではなく43セクションが平均21行で並んでいるため）
- **上限は現状値から始めて手で下げる（ratchet）。** 目標値で入れると常時赤になり、
  「毎日 FAILED が飛ぶと無視される」状態を作る。下げ忘れを防ぐため予算内でも `余裕` を毎回出す
- **`#### ` は親セクションに含め、コードブロックの中は見出しと見なさない。**
  後者が無いと crontab の設定例のコメント行をセクションとして拾う
- 宣言リストや対象ファイルが無いときは skip して通す。pre-commit を壊すほうが害が大きい

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

- **一斉起動しない。** 種別ごとに同時投入数と間隔を絞る（nvim は3個ずつ2秒間隔、claude は
  1個ずつ8秒間隔）。reboot 直後に数十個が同時に立ち上がると負荷スパイクで固まるため
- **nvim のセッションはペイン単位。** cwd 単位だと、同じリポジトリを2ペインで開いたときに
  片方のバッファでもう片方が上書きされる
- 何がどの順で流れるかは `bash scripts/herdr-restore.sh --dry-run` で確認できる

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

投入の刻み方、claude の cwd の戻し方、auto-session のフォールバックが暴れる条件、
進み具合の状態管理は [docs/session-restore-strategy.md](docs/session-restore-strategy.md)。
動作確認は `test-herdr-restore.sh` / `test-herdr-claude-marker.sh` /
`test-herdr-nvim-session-tag.sh` / `test-nvim-session-autosave.sh`。
**後ろ2本は CI では走らない**（実 nvim 設定と auto-session の導入済み環境が要るため
`# ci-skip:` 宣言済み）。

### herdr タブ行のステータス（時計 / CPU / メモリ / LA）

herdr 0.8.2 の `ui.tab_bar_right` で、タブ行の右端に tmux の status-right 相当を出す。
中身は `.config/herdr/scripts/status.sh` が1行で吐く。

```
8/20 Thu 12:09:33 · CPU 30% · MEM 6.1/11.7G · LA 2.12
```

| やりたいこと | コマンド                                               |
| ------------ | ------------------------------------------------------ |
| 出力の確認   | `bash .config/herdr/scripts/status.sh`                 |
| 設定の検証   | `herdr config check`                                   |
| 反映         | `herdr server reload-config`                           |
| 別設定で試す | `env HERDR_CONFIG_PATH=<試作.toml> herdr config check` |
| 動作確認     | `bash scripts/test-herdr-status.sh`                    |

- **native の `datetime` エントリを使わず command 1本に寄せている。** `datetime` は更新間隔を
  持たないので秒を出せない
- **statusline だけを着色する経路が無い。** そのため `status.sh` の着色は既定 `never`
- **`status.sh` は外部コマンドを1つも呼ばない。** 素直に書いた初版は 53ms/回で、1秒間隔だと
  1コアの5%を常時食う。bash 組み込みだけに寄せて 2.6ms にした。ここが唯一の速度要件で、
  可読性より優先する
- **読めない項目は欄ごと落として exit 0。** 1項目のためにステータス全体が消えるほうが害が大きい

色を変えられない事情（`overlay1` が非活性タブのラベルと共有）、CPU% の取り方、
曜日を `%w` から自前で当てる理由は [docs/herdr-ui.md](docs/herdr-ui.md)。

### herdr の keybinding

`config.toml` の `[keys]` は **`prefix = "ctrl+b"` だけを上書きしている**（tmux の指の記憶をそのまま
活かすため）。native アクションは全部デフォルトのままで、足しているのは `[[keys.command]]` の5件だけ。
デフォルト全体は `herdr --default-config` で確認できる。

| キー             | 何をするか                          | 出自   |
| ---------------- | ----------------------------------- | ------ |
| `prefix+a`       | agent を fzf で選んで focus         | 自作   |
| `prefix+t`       | tab を fzf で選んで focus           | 自作   |
| `prefix+shift+s` | workspace を fzf で選んで focus     | 自作   |
| `prefix+f`       | ファイルを fzf で選んでパスを挿入   | 自作   |
| `prefix+alt+g`   | lazygit を popup 起動               | 自作   |
| `prefix+w`       | workspace picker                    | native |
| `prefix+g`       | navigate mode（h/j/k/l の空間移動） | native |
| `prefix+b`       | sidebar のトグル                    | native |

- **fzf popup に寄せているのは alt 併用キーが効かない環境のため。** `prefix+alt+1..9` の
  `focus_agent` などが使えないので、単一 chord から popup を開く方式にしている
- **tab の絞り込み検索は native に無い。** `prefix+g` は空間移動、`prefix+1..9` は番号直打ちで、
  どちらも名前で絞れない

キー割り当てを `a` / `t` / `shift+s` に決めた経緯、picker に space 名を併記する理由、
fzf の終了ステータスを飲む理由は [docs/herdr-ui.md](docs/herdr-ui.md)。
動作確認は `bash scripts/test-herdr-status.sh` / `test-herdr-tab-switch.sh`。

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

**架空名でも辞書に当たる形がある。** `<名前>.slack.com` は架空名を入れても
`.example` 辞書の `[a-z0-9-]+\.slack\.com` に当たるため、**実体辞書では通るのに CI だけが落ちる**。
実在ホストのサブドメインを名乗らせず、`slack.example.com` のように**予約ドメイン側へ寄せる**。
この注意書き自体も、当たる形を本文に書くと検出されるので `<>` で崩してある。

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
