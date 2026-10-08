#!/bin/bash
# nippo-finalize の完了チェック
# 収集フェーズ（Slack / GitHub / Linear）と分析レポートの痕跡が日報にあるかを見る。
# 欠けた項目を stdout に1行ずつ出して exit 1。揃っていれば何も出さず exit 0。
#
# フェーズを飛ばすときは、日報に `<!-- slack: skipped (理由) -->` のような印を残す。
# 印があれば痕跡ありとみなす。黙って飛ばしたフェーズだけを拾うための検査。
#
# 引数: YYYY-MM-DD（省略時は今日）
# 環境変数: NIPPO_DIR - 日報ディレクトリの上書き（テスト用）

set -euo pipefail

DOMAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/paths.sh
source "$DOMAIN_DIR/lib/paths.sh"

NIPPO_FILE="$(nippo_daily_file "$(nippo_resolve_date "${1:-}")")"

if [[ ! -f "$NIPPO_FILE" ]]; then
  echo "- 日報ファイルがありません: $NIPPO_FILE"
  exit 1
fi

missing=0
# $1=痕跡の正規表現（grep -E） $2=欠けていたときの文言
need() {
  if ! grep -qE -- "$1" "$NIPPO_FILE"; then
    echo "- $2"
    missing=1
  fi
}

need '\[Slack/|<!-- slack:' 'Slack: 作業ログに [Slack/ の行も <!-- slack: ... --> の印もない'
need '^## GitHub活動|<!-- github:' 'GitHub: ## GitHub活動 の見出しも <!-- github: ... --> の印もない'
need '^## 今日の作業サマリ（Linear）|<!-- linear:' 'Linear: ## 今日の作業サマリ（Linear） の見出しも <!-- linear: ... --> の印もない'
need '^## Finalize:' 'Finalize: ## Finalize: の分析レポートがない'

exit "$missing"
