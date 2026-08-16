---
name: nippo-show
description: 日報内容を確認する。「日報を見せて」「今日の日報は？」などで使用。
argument-hint: "[日付 YYYY-MM-DD] (省略時は本日)"
allowed-tools: Read, Bash(date:*), Bash(ls:*), Bash(cat:*), Bash(wc:*), Bash(stat:*), Bash(head:*), Bash(find:*), Bash(sort:*), Bash(source:*), Bash(ghq:*)
---

# 日報内容を確認する

`$ARGUMENTS` が指定されている場合はその日付、未指定の場合は本日の日報を表示します。

日報ファイルのパスは `scripts/lib/nippo-paths.sh` の `nippo_daily_file <日付>` が解決します。
**この skill はディレクトリ構造を知りません。**

## 実行内容:

1. **日報ファイルの表示**
   - 対象の日報ファイルが存在する場合、全内容を表示
   - ファイルサイズと最終更新時刻も表示

2. **編集状況の要約**
   - 作業ログのエントリ数
   - 各セクションの記入状況
   - 未記入セクションの警告

3. **過去の日報一覧**
   - 日報ルート（`nippo_root`）配下の過去の日報ファイル一覧（更新時刻の新しい順に5件）

```bash
# 日付の決定（$ARGUMENTS があればその日付、なければ本日）
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/nippo-paths.sh"
TARGET_DATE="$(nippo_resolve_date "${ARGUMENTS:-}")"
NIPPO_FILE="$(nippo_daily_file "$TARGET_DATE")"

echo "📋 日報内容確認 - ${TARGET_DATE}"
echo "================================"

if [ -f "$NIPPO_FILE" ]; then
  echo "📂 ファイル: $NIPPO_FILE"
  echo "📏 サイズ: $(wc -c < "$NIPPO_FILE") bytes"
  echo ""
  echo "📝 内容:"
  echo "--------------------------------"
  cat "$NIPPO_FILE"
  echo ""
  echo "--------------------------------"
  echo ""

  # 簡単な統計情報
  LOG_COUNT=$(grep -c "^### [0-9]" "$NIPPO_FILE" 2>/dev/null || echo "0")
  echo "📊 統計情報:"
  echo " - 作業ログエントリ: ${LOG_COUNT}件"

  # 未記入セクションのチェック
  echo ""
  echo "⚠️ 未記入セクション:"
  grep -n "（後で記入）\|（セッション終了時に記入）\|（随時追記）\|（本日終了時に記入）" "$NIPPO_FILE" | sed 's/^/ - /' || echo " - なし（全て記入済み）"
else
  echo "❌ 日報ファイルが見つかりません: $NIPPO_FILE"
  echo ""
  echo "💡 /nippo-add で作業ログを開始してください。"
fi

echo ""
echo "📅 過去の日報一覧（直近5日分）:"
echo "--------------------------------"
# 日次ファイルは階層の深さが変わりうるので find で拾う。
# mtime 降順に並べたいので、更新時刻を前置してソートする。
find "$(nippo_root)" -type f -name 'nippo.*.md' -printf '%T@ %s %p\n' 2>/dev/null |
  sort -rn | head -5 | while read -r _mtime size path; do
  date_part=$(basename "$path" .md | sed 's/nippo\.//')
  echo "  📄 $date_part ($size bytes)"
done || echo " 過去の日報ファイルはありません"
```
