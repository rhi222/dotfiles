---
name: nippo-guide
description: 日報に対して複数視点からのフィードバックを提供する。「フィードバック」「guide」「ガイド」「アドバイス」「日報を見てもらいたい」「複数視点」などで使用。シニアエンジニア・スタッフエンジニア・ビジネスサイドの3視点でフィードバックする。
disable-model-invocation: true
argument-hint: "[日付 YYYY-MM-DD] (省略時は本日)"
allowed-tools: Read, Write, Edit, Bash(date:*), Bash(ls:*), Bash(cat:*), Bash(wc:*)
---

# 複数視点フィードバック

> 3つの視点からフィードバックを提供し、学ぶべき概念・参考リソースを提示する

## 概要

シニアエンジニア・スタッフエンジニア・ビジネスサイドの3視点で日報の活動を分析し、フィードバックを提供する。断定形は使わず、問いかけの形で気づきを促す。

## 入力・出力

| 項目     | パス                                             | 説明                               |
| -------- | ------------------------------------------------ | ---------------------------------- |
| **入力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md`        | 日報ファイル                       |
| **参照** | `~/Obsidian/02_Daily/nippo-goals.md`             | 目標設定ファイル（オプション）     |
| **出力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md` (追記) | フィードバックを日報に追記         |

## 実行スクリプト

```bash
TARGET_DATE="${ARGUMENTS:-$(date +%Y-%m-%d)}"
NIPPO_FILE="$HOME/Obsidian/02_Daily/nippo.${TARGET_DATE}.md"
GOALS_FILE="$HOME/Obsidian/02_Daily/nippo-goals.md"

echo "🎓 複数視点フィードバック - ${TARGET_DATE}"
echo "================================"

if [ ! -f "$NIPPO_FILE" ]; then
    echo "❌ 日報ファイルが見つかりません: $NIPPO_FILE"
    echo "まず /nippo-add でタスクを記録してください。"
    exit 1
fi

echo "📖 日報内容:"
cat "$NIPPO_FILE"
echo ""

if [ -f "$GOALS_FILE" ]; then
    echo "🎯 目標設定:"
    cat "$GOALS_FILE"
    echo ""
fi

echo "✅ データ読み込み完了"
echo ""
echo "📝 system-prompt.md と output-format.md に従ってフィードバックを生成し、"
echo "   日報ファイルに追記してください。"
```

## 前提条件

- `/nippo-add` で日々のタスクが記録されていること
- 週1〜2回の使用を想定

## AI分析の詳細

- **システムプロンプト**: `system-prompt.md` を参照
- **出力フォーマット**: `output-format.md` を参照
