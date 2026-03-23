---
name: nippo-insight
description: ALACTモデルによる深い振り返りを実施する。「深い振り返り」「insight」「インサイト」「ALACT」「深堀り」などで使用。作業ログから最も学習価値の高い行為を選定し、5段階の振り返りを促す。
disable-model-invocation: true
argument-hint: "[日付 YYYY-MM-DD] (省略時は本日)"
allowed-tools: Read, Write, Edit, Bash(date:*), Bash(ls:*), Bash(cat:*), Bash(wc:*)
---

# ALACTモデル深い振り返り

> 作業ログから最も学習価値の高い行為を1〜2個選定し、ALACTモデル5段階の振り返りを促す

## 概要

ALACTモデル（Action → Looking back → Awareness → Creating alternatives → Trial）に基づき、今日の作業ログから深い学びを引き出す構造化された振り返りセッションを実施する。週1〜2回の使用を想定。

## 入力・出力

| 項目     | パス                                             | 説明                      |
| -------- | ------------------------------------------------ | ------------------------- |
| **入力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md`        | 日報ファイル              |
| **出力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md` (追記) | ALACT振り返りを日報に追記 |

## 実行スクリプト

```bash
TARGET_DATE="${ARGUMENTS:-$(date +%Y-%m-%d)}"
NIPPO_FILE="$HOME/Obsidian/02_Daily/nippo.${TARGET_DATE}.md"

echo "🔬 ALACT深い振り返り - ${TARGET_DATE}"
echo "================================"

if [ ! -f "$NIPPO_FILE" ]; then
    echo "❌ 日報ファイルが見つかりません: $NIPPO_FILE"
    echo "まず /nippo-add でタスクを記録してください。"
    exit 1
fi

NIPPO_SIZE=$(wc -c < "$NIPPO_FILE" 2>/dev/null || echo "0")
if [ "$NIPPO_SIZE" -lt 10 ]; then
    echo "❌ 日報ファイルが空または小さすぎます（${NIPPO_SIZE}バイト）"
    exit 1
fi

echo "📖 日報内容:"
cat "$NIPPO_FILE"
echo ""
echo "✅ データ読み込み完了"
echo ""
echo "📝 system-prompt.md, alact-framework.md, output-format.md に従って"
echo "   振り返りを生成し、日報ファイルに追記してください。"
```

## 前提条件

- `/nippo-add` で日々のタスクが記録されていること
- 作業ログに具体的なエピソードが含まれていること
- 週1〜2回の使用を想定

## AI分析の詳細

- **システムプロンプト**: `system-prompt.md` を参照
- **ALACTフレームワーク**: `alact-framework.md` を参照
- **出力フォーマット**: `output-format.md` を参照
