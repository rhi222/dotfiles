---
name: nippo-trend
description: 時系列分析で長期トレンドを可視化する。「トレンド」「trend」「推移」「長期分析」「傾向」などで使用。指定期間の日報を横断分析し、成長トレンドや停滞パターンを可視化する。
disable-model-invocation: true
argument-hint: "[期間日数] (デフォルト30, 最大90)"
allowed-tools: Read, Write, Bash(date:*), Bash(ls:*), Bash(cat:*), Bash(wc:*), Bash(mkdir:*), Bash(seq:*)
---

# 長期トレンド分析

> 指定期間の日報を横断分析し、4軸の推移・頻出テーマ・作業時間パターン・成長トレンド・停滞パターンを可視化する

## 概要

nippo-weekly が7日固定であるのに対し、nippo-trend は任意期間（デフォルト30日、最大90日）の日報を横断分析する。月1回の使用を想定。

## 入力・出力

| 項目     | パス                                            | 説明                           |
| -------- | ----------------------------------------------- | ------------------------------ |
| **入力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md`       | 指定期間の日報ファイル群       |
| **参照** | `~/Obsidian/02_Daily/nippo-goals.md`            | 目標設定ファイル（オプション） |
| **出力** | `~/Obsidian/02_Daily/nippo-trend.YYYY-MM-DD.md` | トレンド分析レポート           |

## 実行スクリプト

```bash
DAYS="${ARGUMENTS:-30}"
if [ "$DAYS" -gt 90 ]; then
    echo "⚠️ 最大90日です。90日に制限します。"
    DAYS=90
fi

TODAY=$(date +%Y-%m-%d)
TREND_FILE="$HOME/Obsidian/02_Daily/nippo-trend.${TODAY}.md"
NIPPO_DIR="$HOME/Obsidian/02_Daily"
GOALS_FILE="$NIPPO_DIR/nippo-goals.md"

echo "📈 長期トレンド分析 - 過去${DAYS}日間"
echo "================================"

if [ ! -d "$NIPPO_DIR" ]; then
    echo "❌ Obsidianディレクトリが見つかりません: $NIPPO_DIR"
    exit 1
fi

FOUND_COUNT=0
for i in $(seq "$DAYS" -1 0); do
    TARGET_DATE=$(date -d "$i days ago" +%Y-%m-%d)
    NIPPO_FILE="$NIPPO_DIR/nippo.$TARGET_DATE.md"

    if [ -f "$NIPPO_FILE" ]; then
        FOUND_COUNT=$((FOUND_COUNT + 1))
        echo "✓ $TARGET_DATE"
        cat "$NIPPO_FILE"
        echo ""
    fi
done

echo "📊 収集結果: ${FOUND_COUNT}件の日報を発見（${DAYS}日間中）"

if [ "$FOUND_COUNT" -lt 5 ]; then
    echo "❌ エラー: 日報ファイルが5件未満です。トレンド分析には最低5日分必要です。"
    exit 1
fi

if [ -f "$GOALS_FILE" ]; then
    echo "🎯 目標設定:"
    cat "$GOALS_FILE"
    echo ""
fi

echo "✅ データ収集完了"
echo ""
echo "📝 system-prompt.md と output-format.md に従ってトレンド分析を生成し、"
echo "   $TREND_FILE に保存してください。"
```

## 前提条件

- 十分な日報データ（最低5日分）が存在すること
- 月1回程度の使用を想定

## AI分析の詳細

- **システムプロンプト**: `system-prompt.md` を参照
- **出力フォーマット**: `output-format.md` を参照
