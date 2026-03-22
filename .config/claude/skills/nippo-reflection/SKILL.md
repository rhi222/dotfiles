---
name: nippo-reflection
description: 内省的な問いを生成する。「振り返り」「reflection」「内省」「リフレクション」「問いかけ」などで使用。作業ログから具体的エピソードに基づく問いを生成し、回答欄を空白で提示する。
disable-model-invocation: true
argument-hint: "[日付 YYYY-MM-DD] (省略時は本日)"
allowed-tools: Read, Write, Edit, Bash(date:*), Bash(ls:*), Bash(cat:*), Bash(wc:*)
---

# 内省的問いかけ生成

> 今日の作業ログから内省的な問いを5〜7問生成し、回答欄を空白で提示する

## 概要

コルブの経験学習サイクルとギブスのリフレクティブサイクルに基づき、今日の作業ログから具体的エピソードに基づく内省的な問いを生成する。AIは問いを生成するだけで、回答は一切生成しない。

## 入力・出力

| 項目     | パス                                             | 説明                               |
| -------- | ------------------------------------------------ | ---------------------------------- |
| **入力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md`        | 日報ファイル                       |
| **出力** | `~/Obsidian/02_Daily/nippo.YYYY-MM-DD.md` (追記) | 「今日を振り返って一言」後に追記   |

## 実行スクリプト

```bash
TARGET_DATE="${ARGUMENTS:-$(date +%Y-%m-%d)}"
NIPPO_FILE="$HOME/Obsidian/02_Daily/nippo.${TARGET_DATE}.md"

echo "🪞 内省的問いかけ生成 - ${TARGET_DATE}"
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
echo "📝 system-prompt.md と question-frameworks.md に従って問いを生成し、"
echo "   日報ファイルの「今日を振り返って一言」セクション後に追記してください。"
```

## 処理フロー

1. 日報ファイルを読み込む
2. 作業ログから具体的エピソードを抽出
3. `system-prompt.md` と `question-frameworks.md` に従って5〜7問の問いを生成
4. 日報ファイルの「今日を振り返って一言」セクションの後に追記

## 前提条件

- `/nippo-add` で日々のタスクが記録されていること
- 作業ログに具体的なエピソードが含まれていること

## AI分析の詳細

- **システムプロンプト**: `system-prompt.md` を参照
- **問いのフレームワーク**: `question-frameworks.md` を参照
