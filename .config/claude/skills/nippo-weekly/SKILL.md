---
name: nippo-weekly
description: 週次振り返りレポートを生成する
disable-model-invocation: true
---

# 週次振り返りコマンド

> 過去7日間の日報を分析し、週次成長レポートを生成

## 概要

1週間分の日報を集約・分析し、シニアエンジニアとしての週次成長を可視化します。

## 入力・出力

| 項目     | パス                                           | 説明                           |
| -------- | ---------------------------------------------- | ------------------------------ |
| **入力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md`      | 過去7日間の日報ファイル        |
| **参照** | `~/Obsidian/02_Daily/nippo-goals.md`           | 目標設定ファイル（オプション） |
| **出力** | `~/Obsidian/02_Daily/nippo-weekly.YYYY-Wnn.md` | 週次振り返りレポート           |

## 前提条件

- `/nippo-add` で日々の日報が記録されていること
- 最低3日分以上の日報が存在すること
- Obsidianディレクトリが存在すること

## 実行スクリプト

```bash
WEEK_START=$(date -d '6 days ago' +%Y-%m-%d)
WEEK_END=$(date +%Y-%m-%d)
WEEKLY_DIR="$HOME/Obsidian/02_Daily"
WEEK_NUM=$(date +%Y-W%V)
WEEKLY_FILE="$WEEKLY_DIR/nippo-weekly.$WEEK_NUM.md"
NIPPO_DIR="$HOME/Obsidian/02_Daily"
GOALS_FILE="$NIPPO_DIR/nippo-goals.md"

echo "📊 週次振り返り生成"
echo "週番号: $WEEK_NUM"
echo "期間: $WEEK_START 〜 $WEEK_END"

# Phase 1: データ収集
if [ ! -d "$WEEKLY_DIR" ]; then
    mkdir -p "$WEEKLY_DIR"
fi

FOUND_COUNT=0
MISSING_COUNT=0

for i in {6..0}; do
    TARGET_DATE=$(date -d "$i days ago" +%Y-%m-%d)
    NIPPO_FILE="$NIPPO_DIR/nippo.$TARGET_DATE.md"

    if [ -f "$NIPPO_FILE" ]; then
        FOUND_COUNT=$((FOUND_COUNT + 1))
        FILE_SIZE=$(wc -c < "$NIPPO_FILE")
        echo "✓ $TARGET_DATE (${FILE_SIZE}バイト)"
        cat "$NIPPO_FILE"
        echo ""
    else
        MISSING_COUNT=$((MISSING_COUNT + 1))
        echo "⚠️ $TARGET_DATE: ファイルなし"
    fi
done

echo "📊 収集結果: ${FOUND_COUNT}件の日報を発見（${MISSING_COUNT}件なし）"

if [ "$FOUND_COUNT" -lt 3 ]; then
    echo "❌ エラー: 日報ファイルが3件未満です。週次分析には最低3日分必要です。"
    exit 1
fi

if [ -f "$GOALS_FILE" ]; then
    echo "🎯 目標設定:"
    cat "$GOALS_FILE"
    echo ""
else
    echo "ℹ️  目標ファイルが見つかりません（オプション）"
fi

echo "✅ Phase 1 完了: データ収集"

# Phase 2: system-prompt.md と output-format.md に従って分析
# Phase 3: 分析結果を $WEEKLY_FILE に保存
```

## 完了後の表示

```bash
echo "🎉 週次振り返りが正常に完了しました！"
echo "  • 分析対象: ${FOUND_COUNT}日分の日報"
echo "  • 期間: $WEEK_START 〜 $WEEK_END"
echo "  • レポート: $WEEKLY_FILE"

# 過去の週次レポート一覧（直近5週分）
ls -lt "$WEEKLY_DIR"/nippo-weekly.*.md 2>/dev/null | head -5
```

## AI分析の詳細

- **システムプロンプト**: `system-prompt.md` を参照
- **出力フォーマット**: `output-format.md` を参照

## 関連コマンド

- `/nippo-add` - 日報への追記
- `/nippo-finalize` - 日報の完成化
- `/nippo-show` - 日報内容の確認
