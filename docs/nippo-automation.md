# 日報・レポート自動化

## パスの正

日報は `~/Obsidian/02_Daily/` 以下に置く。

| パス                                   | 内容 |
| -------------------------------------- | ---- |
| `daily/YYYY/MM/nippo.YYYY-MM-DD.md`    | 日次 |
| `weekly/YYYY/nippo-weekly.YYYY-Wnn.md` | 週次 |
| `config/nippo-goals.md`                | 目標 |

**skill、script、testはパスを直接組み立てず、`scripts/lib/nippo-paths.sh` を使う。**
`NIPPO_DIR` が `NIPPO_VAULT` より優先され、既定値は関数の呼び出し時に評価する。
階層をまたぐ検索・件数取得は `ls` のglobではなく `find` を使う。

cronの `--allowedTools` はskill frontmatterとは別管理なので、ライブラリ利用には
`Bash(source:*)` / `Bash(ghq:*)` が必要。面談起票を呼ぶ作成cronには `Bash(bash:*)` も必要。

日報skillは `nippo-add` / `nippo-finalize` / `nippo-weekly` / `nippo-reflect` /
`nippo-show` / `nippo-brief` の6本。振り返りは選択コストを増やさないよう
`nippo-reflect` 1本に統合し、モード引数を持たせない。

## 自動化一覧

| 時刻                | 入口                               | enable file                      | 役割                   |
| ------------------- | ---------------------------------- | -------------------------------- | ---------------------- |
| 平日8:00            | `scripts/nippo/create-cron.sh`     | `~/.config/nippo-create-enabled` | 当日日報を作成         |
| 平日9〜19時の奇数時 | `scripts/nippo/notify-cron.sh`     | `~/.config/nippo-notify-enabled` | 日報状態を通知         |
| 平日18:30           | `scripts/nippo/draft-cron.sh`      | `~/.config/nippo-draft-enabled`  | 日報ドラフトを仕上げる |
| 金曜16:00           | `scripts/nippo/esa-weekly-cron.sh` | `~/.config/esa-weekly-enabled`   | esa週次レポートを作る  |

有効化前にdry-runまたは手動実行し、生成物を確認してからcrontabへ登録する。完全なcrontab例と
新環境への移植手順は [bootstrap.md](bootstrap.md) に置く。

### 日報作成

`nippo-create-cron.sh` はテンプレート、当日の予定、前日からの引き継ぎを埋める。
当日ファイルが存在すれば何もせず、手作業を上書きしない。

```fish
env NIPPO_CREATE_DRY_RUN=1 NIPPO_CREATE_FORCE=1 bash scripts/nippo/create-cron.sh
```

### 面談準備

日報作成時に当日と翌営業日の「面談」「面接」を拾い、Linearの `Todo` へ準備タスクを作る。
判断は `nippo-add/interview-prep.md`、状態変更は `scripts/linear/interview-prep.sh` が担当する。

- Google Calendar event idを不変キーにする
- local seen fileとLinear全文検索の二段で重複を防ぐ
- 既存issueを見つけても新情報が無いのでコメントしない
- 実施確定の予定なので `Triage` ではなく `Todo` にする
- 定例の `1on1` は対象外
- 実名、メール、資料URLは日報とLinearだけに置き、repoのtestは架空値を使う

### 日報ドラフト

`nippo-draft-cron.sh` は `nippo-finalize` をヘッドレス実行し、GitHub活動も収集する。
`gh auth status` が通らない場合はGitHubフェーズだけskipして続行する。

```fish
env NIPPO_DRAFT_FORCE=1 bash scripts/nippo/draft-cron.sh
```

### esa週次レポート

`esa-weekly-cron.sh` は `esa-weekly-report` skillを実行し、既定では
`~/Obsidian/05_Organization/Buchokai/` にdraftを出す。出力先は `ESA_WEEKLY_OUT` で変更できる。
`~/Obsidian` はWindows側Vaultへのsymlinkであることを前提とし、新環境で実ディレクトリを
誤作成しない。

## 通知

Claude CodeのStop/Notification hookと日報cronからBurntToastを呼ぶ。共通処理は
`scripts/lib/{notify-windows-toast,stop-notification,notify-cooldown}.sh`。

Stopは最後のassistant発言、cronは継続する日報状態を通知する。
通知本文、実行ゲートとcooldown、状態のreset方法、判定表は
[notifications.md](notifications.md) を参照する。
