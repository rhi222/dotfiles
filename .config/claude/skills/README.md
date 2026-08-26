# Claude専用スキル

## ディレクトリ構成

共用・Claude専用・Codex専用・vendoredの配置と配布規則は
`docs/agent-skills.md` を参照する。このディレクトリにはClaude固有のskillだけを置く。

- Claude専用スキルは `dotfilesLink.sh` が `.config/claude/skills/*/` を `~/.claude/skills/` へ
  シンボリックリンクする。`<name>-workspace/`（skill-creator の作業ディレクトリ）は
  スキルではないのでリンク対象外・gitignore 対象
- 外部スキルは `gh skill` で `~/.claude/skills/` に直接インストールする。
  宣言リストは `scripts/claude-skills.txt`（管理コマンドは CLAUDE.md の
  「Claude Code skill管理」を参照）

### 自作スキル一覧

| スキル                 | 説明                                          |
| ---------------------- | --------------------------------------------- |
| backport-pr            | 既存PRを別ベースブランチ向けPRへ移植          |
| difit                  | ステージ差分のブラウザレビュー                |
| doc-refine             | 文書の論理批評→AIくささ修正パイプライン（humanizeを内部参照） |
| esa-api                | esa.io API共通ナレッジ (他esa-*から内部参照)  |
| esa-diff-weekly        | esa週次差分URL取得&サマリ                     |
| esa-weekly-report      | esa週次エグゼクティブレポート生成             |
| executive-report       | 部長会用の役員報告リライト                    |
| linear-add             | Linear起票（規約の自動適用）                  |
| linear-recall          | 起票済みLinear issueの検索・想起              |
| linear-slack-sweep     | Slackスタンプ→Linear Triage起票               |
| linear-triage          | 夕方triage支援（夜間dispatchの仕込み）        |
| pr-auto-update         | PRの自動更新（タイトル/説明文の再生成）       |
| pr-feedback            | PRレビューコメント分類と対応順序の決定        |
| pr-generate            | PR本文生成（commit履歴からタイトル/説明文を作成） |
| pr-review              | PR内容のセルフレビュー                        |
| pr-watch               | PRの定期監視（レビュー対応・CI修正の自動化）  |
| puml-from-drawio       | draw.io→PlantUML変換                          |
| nippo-\*               | 日報システム（後述）                          |
| session-patterns       | セッション履歴から繰り返しパターンを抽出      |

---

# 日報スキルシステム

## 設計哲学

**「自動化する領域と人間が考える領域を厳密に分離する」**

AIは事実の収集・整理・構造化を担当し、内省・判断・意思決定は人間が行う。
AIが「学び・気づき」を代筆したり、「次の一手」を決定することは、内省を外注している状態であり、成長の機会を奪う。

| 領域         | AIの責務          | ユーザーの責務  |
| ------------ | ----------------- | --------------- |
| 事実の整理   | ✅ 自動生成       | -               |
| 時間集計     | ✅ 自動計算       | -               |
| 候補の提示   | ✅ 選択肢を並べる | ✅ 最終決定     |
| 問いの生成   | ✅ 良い問いを作る | ✅ 自分で答える |
| 学び・気づき | ❌ 生成しない     | ✅ 自分の言葉で |
| 行動の決定   | ❌ 決めない       | ✅ 自分で選ぶ   |

## 4層構造 + 完成化

```
┌─────────────────────────────────────────────────┐
│ 自動収集層: 事実の記録・整理                       │
│   nippo-add / nippo-show / nippo-brief            │
├─────────────────────────────────────────────────┤
│ 内省層: 問いかけによる振り返り                     │
│   nippo-reflect                                   │
├─────────────────────────────────────────────────┤
│ 俯瞰層: 長期的な分析                              │
│   session-patterns                                │
├─────────────────────────────────────────────────┤
│ 完成化: 日報・週報の仕上げ                        │
│   nippo-finalize / nippo-weekly                   │
└─────────────────────────────────────────────────┘
```

## 全スキル一覧

| コマンド            | 説明                         | 引数         | 使用頻度 | 出力先       |
| ------------------- | ---------------------------- | ------------ | -------- | ------------ |
| `/nippo-add`        | 日報作成・追記               | `<追記内容>` | 毎日     | 日報ファイル |
| `/nippo-show`       | 日報全文表示                 | `[日付]`     | 随時     | 標準出力     |
| `/nippo-brief`      | 日報サマリー表示             | `[日付]`     | 随時     | 標準出力     |
| `/nippo-finalize`   | 日報完成化（事実整理＋空欄） | `[日付]`     | 毎日     | 日報追記     |
| `/nippo-reflect`    | 振り返り（ALACT＋別視点）    | `[日付]`     | 任意     | 日報追記     |
| `/nippo-weekly`     | 週次振り返りレポート         | `[週番号]`   | 週1回    | 独立ファイル |
| `/session-patterns` | セッションパターン分析       | `[期間日数]` | 週1回    | 標準出力     |

## 推奨日次フロー

| 時間帯     | スキル                   | 目的                                 |
| ---------- | ------------------------ | ------------------------------------ |
| 朝         | `/nippo-add`             | 日報作成・タスク確認                 |
| 日中       | `/nippo-add start:/end:` | 作業ログ記録                         |
| 業務終了前 | `/nippo-finalize`        | 事実の自動整理（内省欄は空白）       |
| 業務終了時 | `/nippo-reflect`         | 問いに自分で答える（5〜10分）        |
| 必要に応じ | `/nippo-brief`           | 今日のサマリー確認                   |
| 週次       | `/nippo-weekly`          | 週次レポート（セッション分析含む）   |
| 週次       | `/session-patterns`      | セッションパターン分析（単独実行時） |

## 各スキルの詳細

### 自動収集層

#### `/nippo-add` - 日報作成・追記

日報ファイルの作成と追記を行う。新規作成時はLinearから今日のタスクを転記し、nippo-goals.mdから目標逆算タスクを提案する（前営業日からの未完了タスク引き継ぎは行わない。タスク管理はLinearに集約しているため）。`start:`/`end:` で作業時間を計測できる。

#### `/nippo-show` - 日報全文表示

指定日（デフォルト本日）の日報ファイルを全文表示する。統計情報（作業ログエントリ数、未記入セクション）も表示。

#### `/nippo-brief` - 日報サマリー

日報の作業ログから事実のみを3〜5項目に要約。時間サマリとタスク状況も表示する。nippo-showが全文表示なのに対し、briefは要点のみ。

### 内省層

#### `/nippo-reflect` - 振り返り

作業ログから最も学習価値の高い行為を**1件だけ**選び、ALACTモデル（Action → Looking back → Awareness → Creating alternatives → Trial）の5段階で問いを立てる。あわせて、その行為に対して最も異なる見方をする1〜2視点（シニアエンジニア / スタッフエンジニア / ビジネスサイド）から観点を添える。**回答はAIが生成せず、ユーザー自身が記入する。**

**モード引数を持たない。** 以前は `nippo-reflection` / `nippo-insight` / `nippo-guide` の3つに分かれていたが、142日分の日報で出力痕跡は計7ファイルしかなかった。原因は finalize の直後に「どれを呼ぶか」を毎回決めさせられることにあるため、1本にまとめている。

### 完成化

#### `/nippo-finalize` - 日報完成化

日報の作業ログを分析し、アウトカム・時間サマリ・軸別進捗・達成基準チェックを自動生成する。**学び・気づき、日次チェックポイント回答、次の一手の最終決定は空欄として提示し、ユーザー自身が記入する。**

#### `/nippo-weekly` - 週次振り返りレポート

過去7日間の日報を集約・分析し、週次成長レポートを生成する。**来週のアクションプランは候補提示のみ、総括はユーザーが自分の言葉で記入する。**

## セットアップ手順

### 前提条件

1. **Obsidianディレクトリ**: `~/Obsidian/02_Daily/` が存在すること
2. **目標設定ファイル**: `~/Obsidian/02_Daily/config/nippo-goals.md` を作成すること（推奨）
   - 4軸の重点目標と達成基準を記載
   - テンプレート: `.config/claude/skills/nippo-add/goals-template.txt`

### パス解決

日報のパスは `scripts/lib/nippo-paths.sh` に集約している。**skill からパスを直接組み立てない。**

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/nippo-paths.sh"
NIPPO_FILE="$(nippo_daily_file "$(nippo_resolve_date "${ARGUMENTS:-}")")"
```

構造は `daily/YYYY/MM/` ・ `weekly/YYYY/` ・ `config/`。詳細は `~/Obsidian/02_Daily/README.md`。

### 使い始める

1. `/nippo-add 最初の作業メモ` で日報を作成
2. 日中は `/nippo-add start:タスク名` と `/nippo-add end:タスク名` で時間計測
3. 業務終了時に `/nippo-finalize` で事実を整理
4. `/nippo-reflect` で問いに答え、内省を深める
