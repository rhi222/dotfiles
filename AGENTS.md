# AGENTS.md

## リポジトリ概要

各種開発ツールとアプリケーションの設定を、symlinkとコピー同期で複数端末へ配る個人用
dotfilesリポジトリ。

**このファイルは毎セッション読まれる。** 常時必要な安全条件、コマンド索引、設計の境界だけを
置く。実装理由、実測、失敗の記録、個別機能の詳細は `docs/` に置き、対象を触るときだけ読む。

| 文書                                                                 | いつ開くか                                     |
| -------------------------------------------------------------------- | ---------------------------------------------- |
| [docs/bootstrap.md](docs/bootstrap.md)                               | 新端末の立ち上げ、機密ファイル台帳、cron登録   |
| [docs/migration.md](docs/migration.md)                               | PC移行でrepository群と作業状態を運ぶ           |
| [docs/system-management.md](docs/system-management.md)               | ローカル設定、同期、更新、plugin管理を触る     |
| [docs/claude-skills.md](docs/claude-skills.md)                       | Claude skillの信頼境界とvendoringを変える      |
| [docs/scripts-layout.md](docs/scripts-layout.md)                     | scripts、tests、dotctlの構成と公開入口を変える |
| [docs/nippo-automation.md](docs/nippo-automation.md)                 | 日報、面談準備、esa、cronを触る                |
| [docs/linear-command-layer.md](docs/linear-command-layer.md)         | Linearの起票規約、state、Cycle、dispatchを触る |
| [docs/development-workflows.md](docs/development-workflows.md)       | Git hook、gf、設定構造、文書予算を触る         |
| [docs/worktree.md](docs/worktree.md)                                 | worktreeの初期化・掃除の判定を変える           |
| [docs/git-worktree-tool.md](docs/git-worktree-tool.md)               | `git wt` 自体の使い方を調べる                  |
| [docs/session-restore-strategy.md](docs/session-restore-strategy.md) | `he` のherdr/nvim/claude復元を触る             |
| [docs/herdr-ui.md](docs/herdr-ui.md)                                 | herdrのtab statusとkeybindingを変える          |
| [docs/notifications.md](docs/notifications.md)                       | Windows toastの内容・抑止条件を変える          |
| [docs/docker-clean.md](docs/docker-clean.md)                         | `dclean` の判定・閾値を変える                  |
| [docs/public-repository-policy.md](docs/public-repository-policy.md) | 機密情報の置き場所・scan規則を変える           |

## 常時守る境界

### public repository

**社名、社内host、社内repository名、Jira project key、案件code、顧客略号をcommitしない。**
実値はrepo外またはgitignore対象に置き、repoには `.example` と架空値だけを置く。

- 社内context: `~/.claude/local-context.md`
- 機密語辞書: `~/.config/dotfiles/secret-patterns.txt`
- testのhost名: 実在serviceのsubdomainを避け、予約domainを使う
- path名もscan対象。社内名を含む場合は親directory単位でignoreする
- `--no-verify` は原則使わない

検査は `bash scripts/secret-scan.sh --tree`。詳細は
[docs/public-repository-policy.md](docs/public-repository-policy.md)。

### 破壊操作と同期

- cleanup、adopt、削除はdry-runを既定とし、変更には `--execute` を要求する
- symlink先に実ファイルがあれば上書きせず退避する
- 双方向同期に見える機能も正を1つに決める。競合時は拒否し、上書きは `--force` を要求する
- 壊れたJSONや不完全なarchiveを反対側へ伝播しない
- testは実 `$HOME`、実ghq root、現在のworktree、固定 `/tmp/<name>` を変更しない

### 実装言語

- launcher、bootstrap、外部command数個の直列実行はShell
- 複数の状態を集めて判定する処理、JSON、実行計画はGo製 `dotctl`
- skillが `source` する `lib/nippo-paths.sh` と `lib/linear-api.sh` はShell APIを維持する
- 公開入口は `scripts/*.sh`。Goへ移しても薄いwrapperを残し、cron・hook・skillのpathを壊さない
- 新しいtestは `tests/<domain>/test-*.sh`、Go unit testは対象packageと同じdirectory

## セットアップと検証

### 新環境

`dotfilesLink.sh` だけでは完了しない。gitignoreされた認証情報・端末固有値の準備も必要。

```fish
ghq get rhi222/dotfiles
cd (ghq root)/github.com/rhi222/dotfiles
bash scripts/apt-setup.sh
./dotfilesLink.sh
bash scripts/setup-dotctl.sh  # miseでGoを導入した後
```

残りの移植、外部tool、自動化、機密ファイル台帳は [docs/bootstrap.md](docs/bootstrap.md)。

### 変更後の標準検証

```fish
bash scripts/lint.sh
bash scripts/secret-scan.sh --tree
bash scripts/run-tests.sh
bash scripts/doc-budget.sh
bash scripts/ref-check.sh
```

`run-tests.sh` は `tests/<domain>/` のShell testと `go test ./...` を並列実行する。
Shell testは `mktemp` で独立させる。CI不能ならfile headerに `# ci-skip: <理由>`、
並列不能なら `# serial: <理由>` を宣言する。

## 設定の配布と同期

### symlink

`./dotfilesLink.sh` がGit、Neovim、Fish、tmux、mise、Claude Codeなどを配置する。
ローカル設定の実体は `~/.local/share/dotfiles-private/` に集約する。

| 操作           | コマンド                                         |
| -------------- | ------------------------------------------------ |
| 旧環境から集約 | `bash scripts/private-bundle.sh adopt --execute` |
| export         | `bash scripts/private-bundle.sh export`          |
| import         | `bash scripts/private-bundle.sh import <zip>`    |
| 状態確認       | `bash scripts/private-bundle.sh status`          |

`~/.claude/settings.json` とWindows側設定はアプリがrenameで書き戻すためsymlinkにしない。
**どちらも実ファイルを正、repoを追従側とする。**

| 対象             | status                            | 実体 → repo | repo → 実体      |
| ---------------- | --------------------------------- | ----------- | ---------------- |
| Claude settings  | `sync-claude-settings.sh status`  | `pull`      | `push [--force]` |
| Windows settings | `sync-windows-settings.sh status` | `pull`      | `push [--force]` |

Windows同期は末尾に `wslconfig` / `terminal` を付けて片方だけ選べる。`.wslconfig` は端末の
物理RAMに依存するため `dotfilesLink.sh` から自動pushしない。詳細は
[docs/system-management.md](docs/system-management.md)。

## toolとpluginの管理

| 対象                  | 宣言・実体                             | 追加・reconcile                                     |
| --------------------- | -------------------------------------- | --------------------------------------------------- |
| apt                   | `scripts/apt-packages.txt`             | `bash scripts/apt-setup.sh`                         |
| gh extension          | `scripts/gh-extensions.txt`            | `bash scripts/setup-gh-extensions.sh`               |
| fish plugin           | `.config/fish/fish_plugins`            | `bash scripts/setup-fish-plugins.sh`                |
| yazi plugin           | `.config/yazi/package.toml`            | `ya pkg add` / `bash scripts/setup-yazi-plugins.sh` |
| trusted Claude skill  | `scripts/trusted-skill-owners.txt`     | `bash scripts/skill-add.sh <owner/repo> <skill>`    |
| vendored Claude skill | `.config/claude/skills-vendor/<name>/` | `bash scripts/skill-vendor.sh add ...`              |
| Codex自作skill        | `.config/codex/skills/<name>/`         | `./dotfilesLink.sh`                                 |

`daily-update.sh` は導入済みのものを更新するだけで、新規追加しない。1ステップの失敗で止めず、
最後に失敗を集約する。worktreeや環境残骸などの情報提供checkは全体をFAILEDにしない。

### Claude skillの信頼境界

- allowlistはdefault-deny。個人accountをtrustedへ入れない
- allowlist外はvendoringし、codeと `.vendor.json` をcommitして `git diff` でreviewする
- 未検証skillをClaudeへ読ませない。auditが0件でも人が承認する
- `~/.agents/skills` 全体をsymlinkせず、skill単位で外部skillと共存する

コマンドとfail-closed条件は [docs/claude-skills.md](docs/claude-skills.md)。

## dotctlとscripts

Go製 `dotctl` が複雑な状態判定を担い、従来の `scripts/*.sh` wrapperが入口を維持する。
機能固有のShell実装は `domains/<domain>/` に集約し、公開pathから互換層を介して呼ぶ。
現在の適用先は `domains/{linear,nippo}/`。境界と追加基準は
[docs/scripts-layout.md](docs/scripts-layout.md)。

| 機能                       | 既存入口                                    |
| -------------------------- | ------------------------------------------- |
| worktree cleanup / init    | `scripts/worktree-{cleanup,init}.sh`        |
| settings sync              | `scripts/sync-{claude,windows}-settings.sh` |
| skill audit / vendor       | `scripts/skill-{audit,vendor}.sh`           |
| private bundle             | `scripts/private-bundle.sh`                 |
| WSL cleanup                | `scripts/wsl-cleanup.sh`                    |
| residue / migration doctor | `scripts/{env-residue,migration-check}.sh`  |
| docker clean               | `dclean`（fish function）                   |

buildは `bash scripts/setup-dotctl.sh`。新command、wrapper、test配置、移植の評価結果は
[docs/scripts-layout.md](docs/scripts-layout.md)。

## 自動化

### Linear

Linearはtask本体ではなく、Jira / GitHub / Slack / esaへの**pointerを束ねる個人司令塔**。
共有systemへ個人管理の情報を書き戻さず、linkは Linear → 外部の一方向にする。

| 操作              | 入口                                   |
| ----------------- | -------------------------------------- |
| 初期設定          | `bash scripts/linear-bootstrap.sh`     |
| 起票              | `/linear-add`                          |
| draft PR sweep    | `bash scripts/linear-sweep.sh`         |
| Slack stamp sweep | `/linear-slack-sweep`                  |
| recall            | `/linear-recall <URL or keyword>`      |
| 夜間dispatch      | `bash scripts/linear-dispatch-cron.sh` |

stateは「今ボールを誰が持つか」で決める。AI成果物の判断待ちだけ `My Review`、自分の作業は
確認中も `In Progress`。詳細は [docs/linear-command-layer.md](docs/linear-command-layer.md)。

### 日報とレポート

日報pathは必ず `scripts/lib/nippo-paths.sh` で解決し、skillやtestで直書きしない。

| 自動化       | 入口                           | enable file                      |
| ------------ | ------------------------------ | -------------------------------- |
| 当日日報作成 | `scripts/nippo-create-cron.sh` | `~/.config/nippo-create-enabled` |
| reminder     | `scripts/nippo-cron.sh`        | `~/.config/nippo-notify-enabled` |
| 日報draft    | `scripts/nippo-draft-cron.sh`  | `~/.config/nippo-draft-enabled`  |
| esa週報      | `scripts/esa-weekly-cron.sh`   | `~/.config/esa-weekly-enabled`   |

cronの時刻、dry-run、面談準備、allowed toolsは
[docs/nippo-automation.md](docs/nippo-automation.md)。通知内容は
[docs/notifications.md](docs/notifications.md)。

## Git・worktree・session

### GitとPR

- commit conventionは `.config/git/commit-conventions.txt`
- stacked PRは `gh stack` を使う
- Claude hookが非default baseの `gh pr create` を検出してaskする
- `gf` はghq一覧cacheをfzfへ渡し、repository増減後に更新する

詳細は [docs/development-workflows.md](docs/development-workflows.md)。

### worktree

`git wt` 後に `worktree-init.sh` がgitignore対象の `.env*` と依存を初期化する。

| 操作             | コマンド                                             |
| ---------------- | ---------------------------------------------------- |
| 候補確認         | `bash scripts/worktree-cleanup.sh`                   |
| size付き確認     | `bash scripts/worktree-cleanup.sh --size`            |
| 削除             | `bash scripts/worktree-cleanup.sh --execute`         |
| 追跡fileごと削除 | `bash scripts/worktree-cleanup.sh --execute --force` |

cleanupはdry-runが既定。`locked` を最優先でSKIPし、作業中のClaude Code worktreeを消さない。
判定表は [docs/worktree.md](docs/worktree.md)。

### herdr

`he` はherdr layoutに加えてnvim/claude processを復元する。herdrは前面processを保存しないため、
各processがpane単位のmarkerを残す。負荷spikeを避けるため一斉起動しない。

| 操作         | コマンド                                  |
| ------------ | ----------------------------------------- |
| 復元         | `he`                                      |
| 進捗         | `he --status`                             |
| 投入順の確認 | `bash scripts/herdr-restore.sh --dry-run` |
| UI設定の検証 | `herdr config check`                      |
| UI反映       | `herdr server reload-config`              |

復元設計は [docs/session-restore-strategy.md](docs/session-restore-strategy.md)、tab statusとkeyは
[docs/herdr-ui.md](docs/herdr-ui.md)。

## 設定構造

- XDG対応toolは `.config/<tool>/`
- Neovim自作moduleは `.config/nvim/lua/my/{settings,plugins,commands}/`
- Fishは `.config/fish/my/conf.d/` に読込順の番号を付けて機能別に置く
- Neovim pluginはlazy.nvim + `lazy-lock.json`、LSP serverはMason
- runtimeはmiseで管理する
- Docker compose helperは `dc` / `dcl` / `dcu` / `dcd`

Docker cleanupは稼働containerとnamed volumeを削除しない。`dclean` / `dclean -a` の正確な範囲は
[docs/docker-clean.md](docs/docker-clean.md)。

## 文書を増やすとき

- AGENTS.mdにはcommand表と、選択・安全性を左右する不変条件だけを置く
- 実測値、事故の経緯、詳細な判定表、setup例は対象docsへ置く
- 新しい独立機能はAGENTS.mdへ長い節を足さず、docsを作って一覧へ1行追加する
- `scripts/doc-budget.txt` の上限は圧縮後に下げ、超過時に上げて解決しない
- `bash scripts/doc-budget.sh` と `bash scripts/ref-check.sh` で文書を検証する
