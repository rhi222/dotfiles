---
name: nippo-weekly
description: 週次振り返りレポートを生成する。「今週の振り返り」「ウィークリー」「weekly」「週次レポート」「1週間のまとめ」などで使用。過去7日間の日報を分析し、4軸評価トレンドと来週のアクションプランを含む成長レポートを生成する。
disable-model-invocation: true
argument-hint: "[週番号 YYYY-Wnn] (省略時は今週)"
allowed-tools: Read, Write, Bash(date:*), Bash(ls:*), Bash(cat:*), Bash(wc:*), Bash(mkdir:*), Bash(bash:*), Bash(python3:*), Bash(source:*), Bash(jq:*), Bash(ghq:*)
---

# 週次振り返りコマンド

> 過去7日間の日報を分析し、週次成長レポートを生成

## 概要

1週間分の日報を集約・分析し、シニアエンジニアとしての週次成長を可視化します。

## 入力・出力

| 項目     | パス                         | 説明                           |
| -------- | ---------------------------- | ------------------------------ |
| **入力** | `nippo_daily_file <日付>`    | 過去7日間の日報ファイル        |
| **参照** | `nippo_goals_file`           | 目標設定ファイル（オプション） |
| **出力** | `nippo_weekly_file <週番号>` | 週次振り返りレポート           |

パスは `scripts/lib/nippo-paths.sh` が解決する。**この skill はディレクトリ構造を知らない。**

## 前提条件

- `/nippo-add` で日々の日報が記録されていること
- 最低3日分以上の日報が存在すること
- Obsidianディレクトリが存在すること

## 実行スクリプト

```bash
# パス解決は共有ライブラリに委ねる。ここで組み立てない。
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/nippo-paths.sh"
WEEK_START=$(date -d '6 days ago' +%Y-%m-%d)
WEEK_END=$(date +%Y-%m-%d)
# WEEK_NUM は WEEKLY_DIR より先に決める（nippo_weekly_dir が週番号を要求するため）
WEEK_NUM=$(date +%Y-W%V)
WEEKLY_DIR="$(nippo_weekly_dir "$WEEK_NUM")"
WEEKLY_FILE="$(nippo_weekly_file "$WEEK_NUM")"
NIPPO_DIR="$(nippo_root)"
GOALS_FILE="$(nippo_goals_file)"

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
    NIPPO_FILE="$(nippo_daily_file "$TARGET_DATE")"

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

echo "✅ Phase 1 完了: 日報データ収集"

# Phase 2: セッションパターンデータ収集
COLLECT_SCRIPT="$HOME/.config/claude/scripts/collect-session-patterns.sh"

echo ""
if [ -f "$COLLECT_SCRIPT" ]; then
    echo "📋 === セッションパターン分析データ ==="
    DAYS=7 source "$COLLECT_SCRIPT"
else
    echo "ℹ️ セッションパターン収集スクリプトが見つかりません（スキップ）"
fi

echo ""
echo "✅ Phase 2 完了: セッションパターンデータ収集"

# Phase 3: system-prompt.md と output-format.md に従って分析
# Phase 4: 分析結果を $WEEKLY_FILE に保存
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

## Linearラベルによる傾向分析

日報の本文だけでは「何をやったか」しか分からない。**どの職能に時間が寄ったか**は
Linearの `role:*` / `em:*` ラベルでしか見えないので、週次ではここを主軸に据える。

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"
SINCE=$(date -d '6 days ago' +%F)
linear_activity_since "$SINCE" > /tmp/linear-week.json

# role × em のクロス集計
jq -r '[.[] | {r: ([.labels.nodes[].name|select(startswith("role:"))]|first//"role:?"),
               e: ([.labels.nodes[].name|select(startswith("em:"))]|first//"em:?")}]
       | group_by([.r,.e]) | map({k:"\(.[0].r) × \(.[0].e)", n:length}) | sort_by(-.n)[]
       | "\(.n)件\t\(.k)"' /tmp/linear-week.json

# Project別
jq -r '[.[] | .project.name // "（なし）"] | group_by(.)
       | map({p:.[0], n:length}) | sort_by(-.n)[] | "\(.n)件\t\(.p)"' /tmp/linear-week.json

# 完了したもの
jq -r '[.[] | select(.state.type=="completed")] | .[] | "\(.identifier) \(.title)"' /tmp/linear-week.json
```

### 何を読み取るか

**配分の偏りを北極星と突き合わせる。** nippo-goals.md の北極星は
「組織を前に進める人／ただし技術が分かる人であり続ける」なので、両輪が回っているかを見る。

| 観点                            | 見方                                                                                              |
| ------------------------------- | ------------------------------------------------------------------------------------------------- |
| `role:player` vs `role:manager` | playerに寄りすぎ＝組織を前に進める時間が取れていない。managerに寄りすぎ＝技術が分かる人でなくなる |
| `em:*` の欠落                   | 0件の職能があれば名指しする（例: 今週 `em:people` が0件）                                         |
| Project の集中                  | 1つのProjectに偏っていれば、他のIn Progress Projectが止まっている                                 |
| ラベル無し（`role:?` / `em:?`） | 多いとラベル運用が崩れている。件数を報告する                                                      |

### ラベルの週次サンプリング監査

`src:*` は返信先なので事実判定で済むが、`role:*` と `em:*` は判断で付けるため、
間違って付いていても気づけない。週次で**最大5件だけ**抜き取って再推定し、
不一致だけを出す。全件は見ない。目的は個別の誤りを潰すことではなく、傾向的なズレに気づくこと。

```bash
# 直近7日に完了したissueを updatedAt が新しい順に最大5件
jq -r '[.[] | select(.state.type=="completed")] | sort_by(.updatedAt) | reverse | .[0:5] | .[]
       | "\(.identifier)\t\(.title)\t\([.labels.nodes[].name|select(startswith("role:"))]|first//"role:?")\t\([.labels.nodes[].name|select(startswith("em:"))]|first//"em:?")"' \
  /tmp/linear-week.json
```

抜き取った各issueの本文を引き、**タイトルと本文だけを見て** `role:*` と `em:*` を再推定する。

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"
linear_gql 'query($id: String!){ issue(id: $id){ identifier title description } }' \
  "$(jq -n --arg id "NSY-42" '{id:$id}')"
```

判定基準は起票規約と同じ2軸。

- `role:player` = 自分が手を動かした / `role:manager` = 人を動かした
- `em:people` = ヒト（体制・育成・評価） / `em:tech` = 技術 / `em:project` = 案件進行 / `em:product` = プロダクト

現在のラベルと一致していれば何も出さない。**不一致のものだけ**、根拠を1行添えて出す。

```
NSY-42  em:tech → em:project では？
        根拠: 本文が日程調整とベンダー折衝の話に終始している
```

- 完了issueが5件未満の週は全件、0件の週はこのブロックごと省略する
- 抽出窓が7日なので週ごとにほぼ重複しない。**監査済みマーカーは持たない**
- **skillはラベルを付け替えない。** 提案だけして、直すか無視するかは人間が決める
- `src:*` は監査しない

### 書き方の制約

- **毎週同じ観点を並べない。** 前週と比べて動いた軸だけを書く
- **件数を断定的な結論に変換しない。** 「em:people が0件」は事実だが、
  「人に向き合えていない」は解釈。解釈を書くなら根拠（どのissueが動かなかったか）を添える
- Linearにアクセスできない場合はこの節ごと省略し、日報ベースの分析だけで出力する

## AI分析の詳細

- **システムプロンプト**: `system-prompt.md` を参照
- **出力フォーマット**: `output-format.md` を参照

## 関連コマンド

- `/nippo-add` - 日報への追記
- `/nippo-finalize` - 日報の完成化
- `/nippo-show` - 日報内容の確認
- `/session-patterns` - セッションパターン分析（単独実行）
