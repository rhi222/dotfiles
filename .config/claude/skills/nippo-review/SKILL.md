---
name: nippo-review
description: 評価面談・自己評価用の材料を日報から抽出する。「評価材料」「nippo-review」「自己評価」「面談準備」「振り返り材料」「評価面談」などで使用。指定期間の日報を横断分析し、主要成果・成長領域・インパクトを整理する。
disable-model-invocation: true
argument-hint: "[期間日数] (デフォルト30)"
allowed-tools: Read, Write, Bash(date:*), Bash(ls:*), Bash(cat:*), Bash(wc:*), Bash(mkdir:*), Bash(seq:*)
---

# 評価面談材料抽出

> 指定期間の日報を横断分析し、評価面談・自己評価に使える材料を抽出する

## 概要

指定期間（デフォルト30日）の日報を横断分析し、主要成果リスト・成長した領域・数値化できるインパクト・挑戦した領域を整理する。自己評価の「材料」を提示し、評価文そのものは書かない。

## 入力・出力

| 項目     | パス                                                   | 説明                         |
| -------- | ------------------------------------------------------ | ---------------------------- |
| **入力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md`              | 指定期間の日報ファイル群     |
| **参照** | `~/Obsidian/02_Daily/nippo-goals.md`                   | 目標設定ファイル（オプション） |
| **出力** | 標準出力                                               | 評価材料テキスト             |

## 実行スクリプト

```bash
DAYS="${ARGUMENTS:-30}"
TODAY=$(date +%Y-%m-%d)
NIPPO_DIR="$HOME/Obsidian/02_Daily"
GOALS_FILE="$NIPPO_DIR/nippo-goals.md"

echo "📝 評価面談材料抽出 - 過去${DAYS}日間"
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

if [ "$FOUND_COUNT" -lt 3 ]; then
    echo "❌ エラー: 日報ファイルが3件未満です。"
    exit 1
fi

if [ -f "$GOALS_FILE" ]; then
    echo "🎯 目標設定:"
    cat "$GOALS_FILE"
    echo ""
fi

echo "✅ データ収集完了"
echo ""
echo "📝 system-prompt.md と output-format.md に従って評価材料を生成してください。"
echo "   日報には追記せず、標準出力のみ。"
```

## 前提条件

- 十分な日報データ（最低3日分）が存在すること
- 評価面談前の使用を想定

## AI分析の詳細

- **システムプロンプト**: `system-prompt.md` を参照
- **出力フォーマット**: `output-format.md` を参照
