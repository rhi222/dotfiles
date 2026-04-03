---
name: nippo-finalize
description: 日報を完成させる（4軸評価の振り返りレポートを自動生成）。「日報を仕上げて」「振り返り」「finalize」「今日のまとめ」「1日の振り返り」など業務終了時の振り返り生成で使用。
disable-model-invocation: true
argument-hint: "[日付 YYYY-MM-DD] (省略時は本日)"
allowed-tools: Read, Write, Edit, Bash(date:*), Bash(ls:*), Bash(cat:*), Bash(wc:*), mcp__claude_ai_Slack__slack_search_public_and_private
---

# 日報完成化コマンド

> 日々の作業記録を分析し、目標に対する進捗を可視化した構造化レポートを自動生成する

## 概要

本日の日報ドラフトファイルと目標ファイル（nippo-goals.md）を分析し、4軸評価に基づいた振り返りレポートを自動生成して日報に追記します。

## 入力・出力

| 項目     | パス                                             | 説明                         |
| -------- | ------------------------------------------------ | ---------------------------- |
| **入力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md`        | 日報ドラフトファイル         |
| **参照** | `~/Obsidian/02_Daily/nippo-goals.md`             | 目標設定ファイル             |
| **出力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md` (追記) | 分析結果が追記された完成日報 |

## 処理フロー

### 4段階の段階的処理

1. **Phase 1: データ準備・検証**
   - ディレクトリ・ファイルの存在確認
   - ファイルサイズ・読み取り権限の検証

2. **Phase 2: Slack情報収集・作業ログ追記**
   - Slack検索で本人の発言を当日分収集
   - 収集した発言を作業ログ・作業メモに追記

3. **Phase 3: AI分析準備**
   - 日報ドラフトの構造化読み込み
   - 目標設定ファイル（nippo-goals.md）の読み込み

4. **Phase 4: AI分析・レポート生成**
   - `system-prompt.md` のペルソナに従い分析を実行
   - 重点4軸での活動分析
   - 作業ログからの自動セクション生成
   - 時間サマリ生成
   - `output-format.md` のフォーマットで出力

5. **Phase 5: 結果追記**
   - 分析結果を元ファイルに追記

## 前提条件

- `/nippo-add` で日々のタスクが記録されていること
- `~/Obsidian/02_Daily/nippo-goals.md` で目標が設定されていること（推奨）
- Obsidianディレクトリ（`~/Obsidian/02_Daily/`）が存在すること

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
#    query: "from:<@U0E450R1B> on:YYYY-MM-DD"  (YYYY-MM-DDは対象日付)
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

# Phase 3: AI分析準備
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

echo "✅ Phase 3 完了: AI分析準備"

# Phase 4: system-prompt.md と output-format.md に従って分析・レポート生成
# Phase 5: 分析結果を $NIPPO_FILE に追記
```

## 時間サマリ生成

Phase 4 の一部として、作業ログから時間サマリを自動生成します。

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
