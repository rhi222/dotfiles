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

`~/.claude/settings.json` だけは例外でリンクせずコピー同期する（次節）。

### Claude Code settings.json の同期

`~/.claude/settings.json` は **シンボリックリンクにしない**。Claude Code が `/config` でのテーマ変更・プラグインの有効無効・`skillOverrides` などを実行時に書き戻すとき、一時ファイル + rename で置き換えるためリンクが必ず外れて実ファイル化する。`CLAUDE.md` や `commands/` は書き込まれないのでリンクのままでよい。

そこで `scripts/sync-claude-settings.sh` でコピー同期する。**実ファイルを正とし、リポジトリがそれを追いかける**。

| やりたいこと            | コマンド                                            |
| ----------------------- | --------------------------------------------------- |
| 差分の確認              | `bash scripts/sync-claude-settings.sh status`       |
| 実ファイル → リポジトリ | `bash scripts/sync-claude-settings.sh pull`         |
| リポジトリ → 実ファイル | `bash scripts/sync-claude-settings.sh push`         |
| 新環境 bootstrap        | `./dotfilesLink.sh`（内部で `push` する）           |
| 更新                    | `daily-update.sh` が `pull` を自動実行              |

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

| モデル   | 表示                                                       |
| -------- | ---------------------------------------------------------- |
| Fable    | `⚡FABLE 5⚡`（オリーブ背景・カーキ文字・太字の反転バッジ）   |
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

### Linear個人司令塔（タスク集約とAI夜間ディスパッチ）

タスクはLinear（https://linear.app/nsym・team `NSY`）に集約する。**LinearはSoTではなく
「ポインタの司令塔」**で、issueは元URL＋期待アウトカム＋判断状態だけを持つ。本体はJira /
GitHub / Slack / esa 側にある。設計の全体像と根拠は Obsidian
`01_Inbox/2026-08-06-linear-command-layer-design.md`。

| やりたいこと          | コマンド                                                        |
| --------------------- | --------------------------------------------------------------- |
| 初期設定（ID解決）    | `bash scripts/linear-bootstrap.sh`                              |
| 起票                  | `/linear-add`（対話skill。規約を自動適用する）                  |
| draft PR→Triage起票  | `bash scripts/linear-sweep.sh`（cron: 平日8:00）                |
| 夜間ディスパッチ      | `bash scripts/linear-dispatch-cron.sh`（cron: 火-土1:00）       |
| 動作確認              | `bash scripts/test-linear-api.sh` ほか `test-linear-*.sh` 計4本 |

- 認証は `~/.config/linear/api-key`（chmod 600）、設定は `linear-bootstrap.sh` が生成する `config.json`
- 有効化フラグ: `~/.config/linear-sweep-enabled` / `~/.config/linear-dispatch-enabled`
- **スイープはcronだけに頼らない。** WSL2のcronは**PCが停止していた時刻のジョブを実行せず**、
  anacronも入れていないため、8:00に起動していない日は丸ごと落ちる。
  `.config/fish/my/conf.d/14-linear-sweep.fish` がその日の最初の対話シェル起動時にも
  `--if-not-today` 付きで1回だけ走らせて取りこぼしを拾う（`$XDG_STATE_HOME` 相当の
  `~/.local/state/linear-sweep/last-run` で当日実行済みかを判定）。
  cronと併存しても `seen.txt` の重複排除があるので二重起票しない
- 共通ライブラリは `scripts/lib/linear-api.sh`。`linear_issue_create` は**assigneeを自動で自分にする**（未アサインだとMy Issuesに出ないため）

**リンクは Linear → 外部の一方向のみ。GitHub / Jira には一切書き戻さない。**
どちらもチームの共有物なので、個人のタスク管理都合のノイズを持ち込まない。「LinearのNSY-Xと
紐づけました」のような紐づけコメントもしない。ポインタはLinear側にだけ置けば足りる。

- スイープは読み取りAPIのみ使う（`gh` は `search`、Jira は GET）
- 例外はagentが成果物として新規に作るPRだけ。そのPR本文にもLinearのidentifierを書かない
- `test-linear-sweep.sh` は gh stub が `search` 以外で呼ばれると落ちるので、これを検知できる

**スイープ対象は自分のopen draft PRのみ。** 他者PRのレビュー依頼はGitHubの受信箱と二重管理に
なるうえ常時20〜30件あり、Triageが溢れて「人間が選別する受信箱」として機能しなくなる（初回
スイープの実測で27件中22件がレビュー依頼だった）。bot作成PRも除外する
（`LINEAR_SWEEP_EXCLUDE_AUTHORS`、既定 `*[bot]`）。

**夜間ディスパッチは「My Review」が `LINEAR_WIP_LIMIT`（既定10）件以上だと止まる。**
生成速度＞判断速度は仕組みが破綻しているシグナルなので、朝の判断タイムで捌いてから再開する。

- **起動条件は state = `AI Queued` の1点。ラベルは見ない**（パイプライン上の位置はstateで表し、
  ラベルと二重に持たない。`ai:blocked-human` だけは「そもそも委譲できない」属性なのでstateと直交する）
- dispatchは本文の内容で2モードに分かれる

| 本文 | モード | 動作 |
| ---------------- | ------ | ---------------------------------------------------------- |
| 既存PRのURLがある | 継続 | そのPRのブランチをcheckoutして続きを進める。**新規PRは作らない** |
| `repo:` 行のみ | 新規 | `linear/<identifier>` ブランチを切って新規draft PRを作る |

  `draft仕上げ` の子issueは既存draft PRを指しているので継続モードになる。
  新規ブランチ方式のままだと重複PRができていた。継続モードはPRが `OPEN` でなければ実行しない
- worktreeは `<repo>/.wt/linear-<identifier>` に作られ、掃除は `worktree-cleanup.sh` が拾う
- 成果物はdraft PRまで。マージは必ず人間

**push と PR作成はagentではなくスクリプトが行う。** Claude Code は `git push` を許可リストで
上書きできない（`--allowedTools` / settings.json の `permissions.allow` / `acceptEdits` /
`dontAsk` のいずれでも拒否される。`git ls-remote` のような読み取りは通る）。headlessのagentに
任せると必ずPR作成に到達しないため、役割を分ける。

| 担当 | 範囲 |
| ------- | -------------------------------------------------------------- |
| agent | 実装してworktree内でコミットするまで（`gh` を渡さない） |
| スクリプト | `git push` と `gh pr create --draft`（素のbash。権限層を通らない） |

- **PR作成権限はagent実行前に確認する**（`gh repo view --json viewerPermission`）。
  無いまま走らせるとagentを丸ごと1回動かした末に最後だけ失敗する。判定不能な場合も実行しない
- `gh` は業務アカウント `example-org-nishiyama` で認証されている。**個人リポジトリ（`rhi222/*`）は
  `READ` しか無いのでdispatchできない**（`example-org/*` は `ADMIN`）
- コミットが0件ならpushもPR作成もしない（実装に到達しなかったとみなす）

**Cycleは1週間・月曜始まりの宣言型**（Jiraのsprint相当。2026-08-06に有効化）。

| 設定 | 値 | 理由 |
| ---- | ---- | ---- |
| `cycleDuration` | 1（週） | `nippo-weekly` の週次振り返りとリズムを合わせる |
| `cycleStartDay` | **2** | **これで月曜始まりになる**（1は日曜。実測で確認） |
| `cycleIssueAutoAssignStarted/Completed` | false | 自動で入ると「記録」になり、計画と実績の差分が取れない |
| `issueEstimationType` | fibonacci | 親（大）と子（小）が混在するため件数ではvelocityが読めない |

- **Cycleに載せるのは実作業単位。** 子issueがあれば子を、無ければ親を入れる。
  子を持つ親は入れない（二重計上になる）。親課題は複数Cycleにまたがる前提で、
  期限はProjectのtarget dateで追う
- `uncompletedIssuesUponClose` に繰り越しが残るので、**繰り越し回数が滞留の機械的な検出手段**になる
  （created日時より鋭い。「7/3から1ヶ月」のような滞留を3週目で拾える）

**Project名のprefixは判定順で決める**（MECEにしない。先に当たった方が勝ち）。判定するのは
動機ではなく成果物。`worktree-cleanup.sh` の判定表と同じ方式。

| 順  | prefix            | 判定の問い                                       |
| --- | ----------------- | ------------------------------------------------ |
| 1   | `案件_`           | 特定の顧客案件のためだけの仕事か                 |
| 2   | `技術採用_`       | 採用活動そのものか（候補者を探す・口説く・選ぶ） |
| 3   | `組織課題_`       | 対象がヒトか（体制・育成・評価・自分の働き方）   |
| 4   | `QA_`             | 品質の確かめ方が変わるか                         |
| 5   | `プロダクト開発_` | 作るもの・作り方が変わるか                       |
| 6   | `other_`          | どれでもない（受け皿）                           |

issueは**親＝課題（Jiraチケットと1:1）/ 子＝工程**の2階層。**親の単位はJiraが決める**ので、
複数PRを1つの親にまとめる前に各PRのJiraキーが同一かを確認する（見た目の類似でまとめて
あとから割り直した実例あり）。ラベルは直交する2軸で、`role:player` / `role:manager`
（自分が手を動かしたか／人を動かしたか）と `em:people` / `em:tech` / `em:project` /
`em:product`（EMの職能）。Projectは「どの成果物の一部か」、labelは「自分のどの職能の仕事か」
で別の問いに答えるので競合しない。

Jiraの `summary` / `duedate` / 完了条件は claude.ai の Atlassian コネクタで読み込める
（`cloudId` は `example-org.atlassian.net`）。**`status` は同期しない**（Linearのstateは自分の
作業状態で、Jiraの進行状態とは別物）。この経路は対話セッション限定で、cronでは使えない。

**日報からのタスク転記は廃止した**（`nippo-add`）。転記ループは完了を検知せず、終わった
タスクがゾンビとして残り続けたため。実例として「執行役員会の発表準備」は7/3から8/6まで
1ヶ月転記され続けていたが完了済みだった。移行時の棚卸しでは滞留25件のうち11件が
「完了済み or もうやらない」だった。

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

### worktree 一覧のタグ表示（wt / wtd）

`wt` / `wtd` の fzf 一覧の1列目に、その worktree の由来をタグで出す。整形は
`__wt_format_rows`、メインworktreeの解決は `__wt_main_path` に分離している。

| タグ     | 意味                                         |
| -------- | -------------------------------------------- |
| `main`   | メインworktree（本体）                       |
| `.wt`    | `git wt` が作る `.wt/` 配下                  |
| `claude` | Claude Code が作る `.claude/worktrees/` 配下 |
| `wt`     | それ以外の場所にあるリンクworktree           |

**メイン判定は `git worktree list --porcelain` の先頭エントリとの実パス一致で行う。**
以前はパスに `.wt` を含むかだけで見ていたため、`.claude/worktrees/` 配下の worktree が
`[main]` と表示されていた（`.claude` に `.wt` は含まれないため）。逆にメインworktreeの
パスに `.wt` が含まれると `[.wt]` になる誤判定もあった。置き場所が増えても壊れないよう、
「メインかどうか」だけを git に聞き、由来の細分はパスの位置で行う。

タグのパディングは**括弧の外側**に入れる（`[main]  `）。`[main  ]` のように内側へ入れると
`wt` / `wtd` が `awk` で拾うフィールド番号がずれる。

動作確認は `bash scripts/test-wt-select.sh`。

### worktree の掃除

消し忘れた worktree を洗い出して削除する。**既定は dry-run** で、実削除には `--execute` が必要。

| やりたいこと           | コマンド                                             |
| ---------------------- | ---------------------------------------------------- |
| 候補の確認（dry-run）  | `bash scripts/worktree-cleanup.sh`                   |
| 解放見込みつきで確認   | `bash scripts/worktree-cleanup.sh --size`            |
| 実削除                 | `bash scripts/worktree-cleanup.sh --execute`         |
| 追跡ファイルの変更ごと削除 | `bash scripts/worktree-cleanup.sh --execute --force` |
| 動作確認               | `bash scripts/test-worktree-cleanup.sh`              |

`git worktree list --porcelain` を起点にするため、worktree の置き場所を問わず拾える。
`.wt/`（`git wt`）・`.claude/worktrees/`（Claude Code）・`/tmp`・旧 `~/git-worktrees/` が
実際に混在していたが、いずれも走査対象になる。走査ルートの既定は `/data/git-repos`
（`WORKTREE_CLEANUP_ROOTS` で変更可能）。

判定は上から順に評価し、最初にマッチした時点で確定する。

| 順 | 条件                                 | 判定       |
| -- | ------------------------------------ | ---------- |
| 1  | `locked`                             | **SKIP**   |
| 2  | `prunable`（ディレクトリ消失）       | **PRUNE**  |
| 3  | detached HEAD                        | **SKIP**   |
| 4  | 追跡ファイルに未コミット変更あり     | **SKIP**   |
| 5  | PR が MERGED または CLOSED           | **DELETE** |
| 6  | それ以外（OPEN / PRなし / `gh` 失敗） | **KEEP**   |

**`locked` を最優先にしているのが安全性の要。** Claude Code の worktree はセッション実行中に
lock されるため、これを PR 状態より先に判定しないと作業中のディレクトリを消す。`--force` は
ルール4だけを飛ばし、**`locked` は `--force` でも削除しない**（`git worktree remove -f -f` は
実装していない）。`gh` の呼び出しに失敗した場合も KEEP に倒すので、判定不能なときに削除側へ
行くことはない。

**未追跡ファイルは dirty 扱いにしない。** `plans/`（superpowers のスクラッチ）や
レビューメモのような使い捨てファイル1個で、マージ済み worktree の削除がほぼ全部
ブロックされてしまうため（実測で削除候補が6件から1件に落ちた）。ただし黙って消さないよう、
DELETE 行に `（未追跡 N 件あり）` と件数を併記する。N は**未追跡エントリ数**で、
未追跡ディレクトリは配下のファイル数ではなく1件として数える。

**ローカルブランチは削除しない。** そのため CLOSED を削除してもコミット済みの作業はブランチに
残り、消えるのは worktree ディレクトリと `node_modules` 等の再生成可能なファイルだけになる。

`--force` を使うと追跡ファイルの未コミット変更は失われる。その場合 dry-run の DELETE 行に
`（未コミット変更あり・破棄されます）` が併記されるので、実行前に一覧を目視すること。

削除は常に `git worktree remove --force` で行う。git は**未追跡ファイルがあるだけでも
`--force` なしの削除を拒否する**ため、これを付けないと未追跡のみの worktree（＝実際の
削除候補の大半）が消せない。安全性はスクリプトの `--force` フラグではなく上の判定表が
担保している。DELETE に到達するのは locked でも prunable でも detached でもなく、
追跡ファイルがクリーンか利用者が明示的に `--force` を指定したものだけ。
`git worktree remove -f -f`（二重 force）は実装していないので、`locked` は
`--force` を付けても削除されない。

削除に失敗した場合は git のエラーメッセージをそのまま表示する。`git worktree remove` は
**ディレクトリ削除に失敗しても管理エントリだけは消す**ため、孤児ディレクトリが残ることが
ある。そうなると以降 `git worktree list` に出てこず、このスクリプトでは検出できない。
エラーが出たらそのパスを手で確認すること。

`--size` を既定にしないのは `du -sh` が重いため（793MB の worktree で数十秒かかった）。
測定対象も DELETE 候補だけに絞っている。

`daily-update.sh` が毎日 dry-run で候補を数え、**5件以上**で Windowsトースト通知を出す
（閾値は `WORKTREE_CLEANUP_NOTIFY_THRESHOLD`）。このステップは情報提供なので `run_step_soft`
で実行し、`gh` 未認証などで失敗しても daily-update 全体を FAILED にしない。件数は表示行では
なく機械可読なサマリ行 `worktree-cleanup: DELETE_CANDIDATES=N ...` から取る。この行は
dry-run では最終行にならない（後ろに案内が出る）ため `grep '^worktree-cleanup:'` で
行頭アンカーして拾う。

WSL2 のディスクイメージは中で削除しても自動では縮まない。実ディスクの空きを取り戻すには
`bash scripts/wsl-cleanup.sh` の末尾に出る `ext4.vhdx` 圧縮手順を Windows 側で実行する。

### Docker開発

- `find_docker_compose` 関数でcomposeファイルを自動検出
- 略語: `dc` (docker compose), `dcl` (logs), `dcu` (up), `dcd` (down)
- 複数のcomposeファイルの場所と命名パターンをサポート

### Docker の掃除

`dclean`（fish関数）で不要な Docker リソースを掃除する。fish起動時に溜まり具合を1行で通知する。

| やりたいこと | コマンド                                                                        |
| ------------ | ------------------------------------------------------------------------------- |
| 現状確認のみ | `dclean --status`                                                               |
| 軽掃除       | `dclean`（停止コンテナ / dangling image / 匿名volume / 未使用のbuild cache）      |
| 重掃除       | `dclean -a`（軽 + 未使用image全部 + 共有ぶんも含むbuild cache全部）             |
| 使い方       | `dclean --help`                                                                 |
| 動作確認     | `bash scripts/test-docker-clean.sh`                                             |

- **named volume は軽・重どちらでも削除しない。** `docker volume prune` に `-a` を付けないため、未使用でも named volume（DBデータ等）は残る。消すときは `docker volume rm` を明示的に叩く
- **稼働中コンテナも停止しない。** 閾値を超えて稼働しているものを一覧表示するだけで、停止するかは手動判断。一覧の下にコピペ用の停止コマンドを出し、最終行に `dclean --refresh` を添える。`--refresh` を促すのは、停止しただけでは起動時通知がキャッシュのTTLが切れるまで古い件数を出し続けるため（実際になった）。除外パターンで非表示のコンテナが閾値を超えている場合は `（除外 N 件）` を注記する（`docker ps` と件数が合わず不足に見えるのを防ぐため）
- **一覧は種別タグを出し、停止コマンドを種別ごとに分ける。** 停止の可逆性がまるで違うため。判定は `__docker_clean_container_kind` に分離してある

| タグ           | 意味                                          | 案内するコマンド                        |
| -------------- | --------------------------------------------- | --------------------------------------- |
| `[compose]`    | compose 管理で `working_dir` が存在する        | `docker compose -p <project> down`      |
| `[orphan]`     | compose 管理だが `working_dir` が消えている    | 同上（ただし `up` では戻せない）        |
| `[standalone]` | compose 管理外（`docker run` 由来）            | `docker container stop <名前...>`       |

- **判定順が要点。`working_dir` label が空のときは `orphan` にせず `compose` に倒す。** `orphan` は削除を伴う `down` を案内する側なので、孤児だと証明できないものを孤児扱いしてはいけない
- **種別判定はキャッシュ読み出し時に行い、更新時に固定しない。** `test -d` は安いが、更新時に固定すると worktree を消した直後から最大6時間（TTL）`compose` と嘘をつく
- **compose 系は `stop` ではなく `docker compose -p <project> down` を案内する。** `-p` を付ければ compose ファイル無し・任意の cwd から label 経由でプロジェクトを解決でき（Compose v5.4.0 で実機確認）、compose が作った network も一緒に回収される。プロジェクト単位で1行にまとめるので、同一プロジェクトの複数コンテナで重複しない
- **`standalone` は `AutoRemove=true` のとき `※--rm: 停止で削除されます` を併記する。** レシピが docker 側に一切残らないうえ停止＝即削除になるため（実機の example-org-mcp のコンテナがこれ）。復活は起動元のツール経由しかない
- **タグのパディングは括弧の外側に入れる**（`[main]  ` と同じ規約）。ASCII に揃えているので `string pad` の East Asian 文字幅も絡まない
- **種別表示は除外適用後の一覧に対して行う。** 既定の除外パターンはどちらも standalone なので、既定設定では `[standalone]` 行はほぼ出ない。除外リストは「知っていて放置しているもの」の宣言として残している
- **キャッシュには `schema` を持たせ、古い版は TTL 内でも stale 扱いにする。** 種別列（`compose_project` / `compose_dir` / `auto_remove`）を持たないキャッシュを読んでいる間は orphan 件数を出せないため、起動時の background 更新に乗せて次回から正しくする。`running[]` の列を増やしたら `__docker_clean_schema_current` を上げる
- **build cache は全ビルダーを対象にする。** `docker builder prune` は `docker buildx prune` のエイリアスで `--builder` を付けないとカレントビルダーしか掃除しない。docker-containerドライバのビルダーと daemon 側の `default` ビルダーは別のキャッシュを持つ（実測で11.2GBと13.0GB）ため、`__dclean_builders` で列挙して両方に対して実行する
- **`--filter until=<duration>` は使わない。** 実測で docker / docker-container どちらのドライバでも `Total: 0B` になり、7日以上前のレコードが445件残っていても一切回収されなかった。フィルタなしなら同じ状態から5.142GB回収でき `df` の Reclaimable も 0B になる。`docker buildx du` 側も `--filter until=` を無視する（1hでも99999hでも同件数）。そのため軽/重の区別は `-a` の有無だけで付けている
- **通知は「軽掃除で消える分」と「重掃除でしか消えない分」を分けて判定する。** `docker system df` の `Images` Reclaimable は「どのコンテナからも参照されていない image」の量で dangling かは問わない。軽掃除の `image prune -f` は dangling だけを消すため、`Images` を軽掃除の根拠にすると `dclean` しても通知が消え続ける（実際になった）。`Images` 由来が主なら通知は `→ dclean -a` を案内する。`Containers` / `Local Volumes` / `Build Cache` の Reclaimable は軽掃除の prune が回収する量に対応する（実測で prune 後 0B になる）
- **軽モードは image と build cache の回収量を事前に出さない。** dangling image は共有レイヤのため確定できず、build cache は `buildx du` の合算（246件/5.4GB）と実際の回収量（0B）が桁違いになる。`df` の Build Cache Reclaimable は `default` ビルダーの分しか見ないので代わりにもならない。実際の回収量は実行後の `回収:` 行を見る
- **起動時通知は orphan が1件以上のときだけ件数を併記する**（`12h超稼働 3件（orphan 1）`）。確実な停止候補が居るかどうかで「今 `dclean --status` を見る価値があるか」が変わるため。0件なら括弧は付けない
- 意図的に未使用 image を残していて通知が邪魔な場合は `docker_clean_size_threshold_gb` を上げる
- `docker system df` は実測5.2秒かかるため、起動時通知は `$XDG_STATE_HOME/docker-clean/stats.json` のキャッシュを読むだけにしている。キャッシュがTTL（既定6h）を超えている場合の更新は background + disown で行い、結果は次回の起動時に反映される。起動時間への影響はフックあり0.62s / なし0.63sでノイズ以下。**キャッシュを読むだけなので、コンテナを停止しても通知の件数はすぐには変わらない。** 即座に反映したいときは `dclean --refresh`（`dclean` / `dclean --status` の実行でも更新される）
- 閾値と除外リストは変数で上書きできる（`99-local.fish` などで設定する）

| 変数                              | 既定値                             | 意味                                      |
| --------------------------------- | ---------------------------------- | ----------------------------------------- |
| `docker_clean_size_threshold_gb`  | `5`                                | 回収可能サイズがこの値以上なら通知する    |
| `docker_clean_uptime_threshold_h` | `12`                               | この時間を超えて稼働していたら一覧に出す  |
| `docker_clean_ignore_patterns`    | `buildx_buildkit_*` `*example-org-mcp*` | 稼働一覧から除外する名前/イメージのグロブ |
| `docker_clean_cache_ttl_h`        | `6`                                | キャッシュのTTL                           |

除外パターンはコンテナ**名**とイメージ**名**の両方に照合する。`example-org-mcp` のコンテナ名は
`suspicious_gagarin` のように自動生成されるため、イメージ名でしか除外できない。

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
