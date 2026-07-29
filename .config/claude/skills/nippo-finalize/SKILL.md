---
name: nippo-finalize
description: 日報の事実情報を整理して仕上げる（4軸評価レポートを自動生成、内省欄は空白で残す）。「日報を仕上げて」「finalize」「今日のまとめ」「日報を完成」「事実整理」など業務終了時の整理で使用。内省的な問いの生成は nippo-reflection を使う。
disable-model-invocation: true
argument-hint: "[日付 YYYY-MM-DD] (省略時は本日)"
allowed-tools: Read, Write, Edit, Bash(date:*), Bash(ls:*), Bash(cat:*), Bash(wc:*), Bash(command:*), Bash(gh:*), Bash(jq:*), Bash(sort:*), Bash(paste:*), mcp__claude_ai_Slack__slack_search_public_and_private
---

# 日報完成化コマンド

> 日々の作業記録を分析し、目標に対する進捗を可視化した構造化レポートを自動生成する

## 概要

本日の日報ドラフトファイルと目標ファイル（nippo-goals.md）を分析し、4軸評価に基づいた振り返りレポートを自動生成して日報に追記します。Slackの発言とGitHubのPR活動を事実情報として自動収集し、分析の根拠にします。

## 入力・出力

| 項目     | パス                                             | 説明                         |
| -------- | ------------------------------------------------ | ---------------------------- |
| **入力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md`        | 日報ドラフトファイル         |
| **参照** | `~/Obsidian/02_Daily/nippo-goals.md`             | 目標設定ファイル             |
| **出力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md` (追記) | 分析結果が追記された完成日報 |

## 処理フロー

### 段階的処理

1. **Phase 1: データ準備・検証**
   - ディレクトリ・ファイルの存在確認
   - ファイルサイズ・読み取り権限の検証

2. **Phase 2: Slack情報収集・作業ログ追記**
   - Slack検索で本人の発言を当日分収集
   - 収集した発言を作業ログ・作業メモに追記

3. **Phase 3: GitHub活動収集・追記**
   - `gh` で当日の作成PR / マージPR / レビュー状況 / 実施したレビューを収集
   - 「## GitHub活動」セクションとして日報に追記

4. **Phase 4: AI分析準備**
   - 日報ドラフトの構造化読み込み
   - 目標設定ファイル（nippo-goals.md）の読み込み

5. **Phase 5: AI分析・レポート生成**
   - `system-prompt.md` のペルソナに従い分析を実行
   - 重点4軸での活動分析
   - 作業ログ・GitHub活動からの自動セクション生成
   - 時間サマリ生成
   - `output-format.md` のフォーマットで出力

6. **Phase 6: 結果追記**
   - 分析結果を元ファイルに追記

## 前提条件

- `/nippo-add` で日々のタスクが記録されていること
- `~/Obsidian/02_Daily/nippo-goals.md` で目標が設定されていること（推奨）
- Obsidianディレクトリ（`~/Obsidian/02_Daily/`）が存在すること
- Slack情報収集を使う場合: 環境変数 `SLACK_MEMBER_ID` を本人のSlackメンバーIDに設定すること
  (fish: `set -Ux SLACK_MEMBER_ID U0XXXXXXX`)
- GitHub活動収集を使う場合: `gh` CLI が認証済みであること（`gh auth status` / スコープに `repo` が必要）
  未インストール・未認証の場合はPhase 3をスキップして処理を続行する

## 実行スクリプト

```bash
NIPPO_FILE="$HOME/Obsidian/02_Daily/nippo.$(date +%Y-%m-%d).md"
GOALS_FILE="$HOME/Obsidian/02_Daily/nippo-goals.md"

# Phase 1: データ準備・検証
OBSIDIAN_DIR="$(dirname "$NIPPO_FILE")"
if [ ! -d "$OBSIDIAN_DIR" ]; then
    echo "❌ Obsidianディレクトリが見つかりません: $OBSIDIAN_DIR"
    exit 1
fi

if [ ! -f "$NIPPO_FILE" ]; then
    echo "❌ 日報ファイルが見つかりません: $NIPPO_FILE"
    echo "まず /nippo-add でタスクを記録してください。"
    exit 1
fi

if [ ! -r "$NIPPO_FILE" ]; then
    echo "❌ 日報ファイルを読み取れません: $NIPPO_FILE"
    exit 1
fi

NIPPO_SIZE=$(wc -c < "$NIPPO_FILE" 2>/dev/null || echo "0")
if [ "$NIPPO_SIZE" -lt 10 ]; then
    echo "❌ 日報ファイルが空または小さすぎます（${NIPPO_SIZE}バイト）"
    exit 1
fi

echo "✅ Phase 1 完了: データ準備・検証"

# Phase 2: Slack情報収集・作業ログ追記
# 以下の手順でSlackから本人の発言を収集し、日報に追記する
#
# 1. mcp__claude_ai_Slack__slack_search_public_and_private を使用して検索:
#    query: "from:<@${SLACK_MEMBER_ID}> on:YYYY-MM-DD"  (YYYY-MM-DDは対象日付、SLACK_MEMBER_IDは環境変数で設定)
#    sort: "timestamp"
#    sort_dir: "asc"
#    include_context: false
#    limit: 20
#
# 2. 結果が20件の場合、cursorを使って次ページも取得（全件収集するまで繰り返す）
#
# 3. 収集した発言を以下のルールで分類・追記:
#    - 時刻付きの短い発言・報告 → 「## 作業ログ（分報・思考メモ）」セクションに時系列で追記
#      フォーマット: "- HH:MM [Slack/#チャンネル名] 発言内容の要約"
#    - 詳細な議論・意思決定・技術的メモ → 「## 作業メモ」セクションに追記
#      フォーマット: 適切な見出し付きで内容を整理
#
# 4. 追記ルール:
#    - 既に作業ログに記載済みの内容と重複する場合はスキップ
#    - bot向けコマンド（/remind等）やリアクションのみの発言は除外
#    - チャンネル名を付記して文脈がわかるようにする
#    - 作業ログは時系列順を維持する（既存エントリとマージ）
#
# 5. 追記完了後、追記件数を表示

echo "✅ Phase 2 完了: Slack情報収集・作業ログ追記"

# Phase 3: GitHub活動収集
# 当日のPR活動（作成 / マージ / 自分のPRのレビュー状況 / 自分が実施したレビュー）を収集する。
# commit単位は粒度が細かすぎるため収集しない。
TARGET_DATE=$(date +%Y-%m-%d)
DAY_FROM="${TARGET_DATE}T00:00:00+09:00"
DAY_TO="${TARGET_DATE}T23:59:59+09:00"
REVIEW_SINCE=$(date -d "$TARGET_DATE -1 day" +%Y-%m-%d)
BOT='(\[bot\]$)|(^github-actions$)|(^copilot-)'

if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
    echo "ℹ️  gh CLI が未インストールまたは未認証のため GitHub活動の収集をスキップします"
else
    GH_USER=$(gh api user --jq .login)
    echo "## GitHub活動 ($GH_USER)"
    echo

    # (a) 当日作成したPR
    echo "### 作成したPR"
    gh search prs --author @me --created "$DAY_FROM..$DAY_TO" --limit 30 \
        --json number,title,url,repository,state,isDraft |
        jq -r 'if length == 0 then "- なし" else .[] |
          "- [\(.repository.nameWithOwner)#\(.number)] \(.title)（\(if .isDraft then "draft" else .state end)）\n  - \(.url)" end'
    echo

    # (b) 当日マージされた自分のPR
    echo "### マージされたPR"
    gh search prs --author @me --merged-at "$DAY_FROM..$DAY_TO" --limit 30 \
        --json number,title,url,repository |
        jq -r 'if length == 0 then "- なし" else .[] |
          "- [\(.repository.nameWithOwner)#\(.number)] \(.title)\n  - \(.url)" end'
    echo

    # (c) 当日動きのあった自分のオープンPRのレビュー状況
    echo "### 自分のPRのレビュー状況（当日更新分）"
    OPEN_PRS=$(gh search prs --author @me --state open --updated "$DAY_FROM..$DAY_TO" --limit 20 \
        --json number,repository | jq -r '.[] | "\(.repository.nameWithOwner) \(.number)"')
    if [ -z "$OPEN_PRS" ]; then
        echo "- なし"
    else
        echo "$OPEN_PRS" | while read -r repo num; do
            gh pr view "$num" --repo "$repo" \
                --json number,title,url,isDraft,reviewDecision,latestReviews |
                jq -r --arg repo "$repo" --arg bot "$BOT" '
                  (if .isDraft then "draft"
                   elif .reviewDecision == "APPROVED" then "approved"
                   elif .reviewDecision == "CHANGES_REQUESTED" then "changes requested"
                   elif .reviewDecision == "REVIEW_REQUIRED" then "レビュー待ち"
                   else "レビュー未依頼" end) as $status
                | ([.latestReviews[] | select(.author.login | test($bot) | not)
                    | "\(.author.login):\(.state)"] | join(", ")) as $reviewers
                | "- [\($repo)#\(.number)] \(.title) — \($status)"
                  + (if $reviewers == "" then "" else "（\($reviewers)）" end)
                  + "\n  - \(.url)"'
        done
    fi
    echo

    # (d) 当日自分が実施したレビュー
    #     GitHub検索にレビュー日での絞り込みがないため、前日以降に更新されたPRを候補として
    #     取得し、reviews API の submitted_at（JST換算）で当日分に絞る
    echo "### 自分がレビューしたPR"
    REVIEWED=$(gh search prs --reviewed-by @me --updated ">=$REVIEW_SINCE" --limit 50 \
        --json number,repository,title,url,author |
        jq -r '.[] | "\(.repository.nameWithOwner)\t\(.number)\t\(.title)\t\(.author.login)"' |
        while IFS=$'\t' read -r repo num title author; do
            states=$(gh api "repos/$repo/pulls/$num/reviews" --paginate \
                --jq ".[] | select(.user.login == \"$GH_USER\")
                      | select(.submitted_at != null)
                      | select((.submitted_at | fromdateiso8601 + 32400 | strftime(\"%Y-%m-%d\")) == \"$TARGET_DATE\")
                      | .state" | sort -u | paste -sd, -)
            [ -n "$states" ] && echo "- [$repo#$num] $title — $states（author: $author）"
        done)
    echo "${REVIEWED:-- なし}"
    echo

    # (e) 自分に来ているレビュー依頼の滞留件数（当日活動ではないが翌日の着手判断に使う）
    PENDING=$(gh search prs --review-requested @me --state open --limit 100 --json number | jq 'length')
    echo "### レビュー依頼の未処理: ${PENDING}件"
fi

# 上記の出力を日報ファイルの「## GitHub活動」セクションとして追記する。
# 追記ルール:
#   - 既に「## GitHub活動」セクションがある場合は内容を差し替える（重複追記しない）
#   - 「## 作業ログ（分報・思考メモ）」の後、分析レポートより前に配置する
#   - 「- なし」ばかりの場合もセクションは残す（活動がなかった事実を記録する）

echo "✅ Phase 3 完了: GitHub活動収集・追記"

# Phase 4: AI分析準備
echo "📖 日報内容:"
cat "$NIPPO_FILE"
echo ""

if [ -f "$GOALS_FILE" ]; then
    echo "🎯 目標設定:"
    cat "$GOALS_FILE"
    echo ""
else
    echo "ℹ️  目標ファイルが見つかりません（オプション）"
fi

echo "✅ Phase 4 完了: AI分析準備"

# Phase 5: system-prompt.md と output-format.md に従って分析・レポート生成
# Phase 6: 分析結果を $NIPPO_FILE に追記
```

## GitHub活動収集の詳細

| 収集項目               | 使用コマンド                                                                                           | 備考                                                         |
| ---------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------ |
| 作成したPR             | `gh search prs --author @me --created`                                                                 | 日付範囲は `+09:00` 付きで指定しJSTの1日に揃える             |
| マージされたPR         | `gh search prs --author @me --merged-at`                                                               | 同上                                                         |
| 自分のPRのレビュー状況 | `gh search prs --author @me --state open --updated` → `gh pr view --json reviewDecision,latestReviews` | 当日更新分のみ。bot（github-actions/copilot等）は除外        |
| 自分が実施したレビュー | `gh search prs --reviewed-by @me` → `gh api repos/../pulls/../reviews`                                 | GitHub検索にレビュー日フィルタがないため submitted_at で絞る |
| レビュー依頼の滞留     | `gh search prs --review-requested @me --state open`                                                    | 件数のみ                                                     |

- **commit単位は収集しない**。粒度が細かすぎて日報のノイズになるため、PR単位に留める。
- 過去日を指定した場合、「自分が実施したレビュー」は対象PRがその後さらに更新されていると検索候補から漏れる可能性がある（当日実行が前提）。

## 時間サマリ生成

Phase 5 の一部として、作業ログから時間サマリを自動生成します。

1. **作業ログの解析**: `🟢 start:` と `🔴 end:` の行を抽出し、時刻とタスク名をパース
2. **時間計算**: 同じタスク名の start/end ペアをマッチングし経過時間を計算
3. **サマリ生成**: テーブル形式で出力
4. **警告表示**: 未終了タスクがあれば警告を追記

### 時間フォーマット

- 60分未満: `45m`
- 60分以上: `1h15m`
- 時間がない場合: `--`

## AI分析の詳細

- **システムプロンプト**: `system-prompt.md` を参照
- **出力フォーマット**: `output-format.md` を参照
