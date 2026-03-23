---
name: session-patterns
description: セッション履歴から繰り返し作業パターンを分析しスキル化候補を提示する。「パターン分析」「session-patterns」「スキル候補」「繰り返し作業」「自動化候補」などで使用。
disable-model-invocation: true
argument-hint: "[日数 N] (デフォルト7, 最大30)"
allowed-tools: Read, Bash(date:*), Bash(python3:*), Bash(ls:*), Bash(bash:*)
---

# セッションパターン分析

> セッション履歴から繰り返し作業パターンを発見し、スキル化候補を提示する

## 概要

過去N日間（デフォルト7日）のClaude Codeセッション履歴を全プロジェクト横断で分析し、繰り返しパターンやスキル化の候補を提示します。

## 入力・出力

| 項目     | パス                                         | 説明                                   |
| -------- | -------------------------------------------- | -------------------------------------- |
| **入力** | `~/.claude/history.jsonl`                    | 全プロジェクト横断のプロンプト履歴     |
| **入力** | `~/.claude/projects/*/sessions-index.json`   | セッション単位のメタデータ             |
| **出力** | 標準出力                                     | 分析結果（ファイル保存なし）           |

## 実行スクリプト

```bash
DAYS="${ARGUMENTS:-7}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT_SCRIPT="$SCRIPT_DIR/../../scripts/collect-session-patterns.sh"

if [ ! -f "$COLLECT_SCRIPT" ]; then
    echo "❌ データ収集スクリプトが見つかりません: $COLLECT_SCRIPT"
    exit 1
fi

DAYS="$DAYS" source "$COLLECT_SCRIPT"
```

## 前提条件

- `~/.claude/history.jsonl` が存在すること
- python3 が利用可能であること

## AI分析の詳細

- **システムプロンプト**: `system-prompt.md` を参照
- **出力フォーマット**: `output-format.md` を参照

## 関連コマンド

- `/nippo-weekly` - 週次振り返りレポート（セッションパターン分析セクションを含む）
- `/nippo-trend` - 長期トレンド分析
