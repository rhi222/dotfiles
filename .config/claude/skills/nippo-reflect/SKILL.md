---
name: nippo-reflect
description: 日報の作業ログから振り返りを促す。「振り返り」「reflect」「内省」「リフレクション」「深掘り」「フィードバック」「今日の学び」などで使用。学習価値の高い行為を1件選び、ALACTの型で問いを立て、他視点の観点を添える。回答欄は空白で残す。
disable-model-invocation: true
argument-hint: "[日付 YYYY-MM-DD] (省略時は本日)"
allowed-tools: Read, Write, Edit, Bash(date:*), Bash(ls:*), Bash(cat:*), Bash(wc:*), Bash(source:*), Bash(ghq:*)
---

# 振り返り

> 今日の作業ログから最も学習価値の高い行為を1件選び、ALACTの型で問いを立て、他視点の観点を添える

## 設計方針

**モード引数を持たない。** 以前は `nippo-reflection`（内省の問い）・`nippo-insight`（ALACT）・
`nippo-guide`（3視点）の3 skill に分かれていたが、142日分の日報で出力痕跡は計7ファイルだった。
原因は `/nippo-finalize` の直後に「どれを呼ぶか」を毎回決めさせられることにある。
モード分岐を残すと同じ判断コストが戻るため、1本の流れにまとめている。

## 入力・出力

| 項目     | 解決関数                        | 説明                     |
| -------- | ------------------------------- | ------------------------ |
| **入力** | `nippo_daily_file <日付>`       | 日報ファイル             |
| **参照** | `nippo_goals_file`              | 目標設定（オプション）   |
| **出力** | `nippo_daily_file <日付>`(追記) | 振り返りを日報に追記     |

パスは `scripts/lib/nippo-paths.sh` が解決する。**この skill はディレクトリ構造を知らない。**

## 前提

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/nippo-paths.sh"
TARGET_DATE="$(nippo_resolve_date "${ARGUMENTS:-}")"
NIPPO_FILE="$(nippo_daily_file "$TARGET_DATE")"
GOALS_FILE="$(nippo_goals_file)"

if [ ! -f "$NIPPO_FILE" ]; then
  echo "❌ 日報が見つかりません: $NIPPO_FILE"
  exit 1
fi
```

## 手順

1. `$NIPPO_FILE` の「作業ログ（分報・思考メモ）」と「作業メモ」を読む
2. **学習価値の高い行為を1件選ぶ。** 判断基準は `alact-framework.md` の
   「振り返り対象の選定基準」に従う。時間をかけた作業ではなく、
   **判断が分かれた場面・想定と結果がズレた場面**を優先する
3. 選んだ行為について、`alact-framework.md` の5段階に沿って問いを立てる
4. `question-frameworks.md` から、その行為の性質に合う問いを2〜3問足す
5. シニアエンジニア / スタッフエンジニア / ビジネスサイドのうち、
   **その行為に対して最も異なる見方をする1〜2視点**から観点を添える。
   3視点を機械的に並べない
6. `output-format.md` の形式で、`$NIPPO_FILE` の**末尾**に追記する。
   「💡 学び・気づき」の直後に挟まない（`/nippo-finalize` の一体のレポートが分断されるため）

## 出力の原則

- **回答は書かない。** 問いと空欄だけを置く。AIが埋めると振り返りにならない
- 問いは今日の具体的なエピソードに紐づける。「どう感じましたか」のような一般論にしない
- open-ended にする（Yes/No で答えられる形にしない）
- 非断定的にする（「〜すべき」ではなく「〜について、どう考えましたか」）
- **選ばなかった行為には触れない。** 1件に絞ることが価値

## 参照

| ファイル                  | 内容                                       |
| ------------------------- | ------------------------------------------ |
| `alact-framework.md`      | ALACTモデルの5段階と、振り返る行為の選定基準 |
| `question-frameworks.md`  | 問いの型のカタログと問い生成のルール       |
| `output-format.md`        | 日報への追記フォーマット                   |
