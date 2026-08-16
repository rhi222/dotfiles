#!/bin/bash
# 日報（nippo）のパス解決。全 nippo skill と cron スクリプトがここを通す。
#
# 読み込み:
#   source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/nippo-paths.sh"
#
# 環境変数（テスト・別環境向けの差し替え）:
#   NIPPO_VAULT  Vault のルート  （既定: $HOME/Obsidian）
#   NIPPO_DIR    日報のルート    （既定: $(nippo_vault)/02_Daily）
#
# 既存の2系統をそのまま尊重する。NIPPO_DIR は nippo-check.sh とそのテストが、
# NIPPO_VAULT は cron 2本が既に使っている。新しい名前を増やさない。
#
# 既定値は変数に焼き込まず、関数が呼ばれるたびに $HOME を評価する。
# ~/Obsidian は Windows 側 Vault への symlink で、テストが $HOME を
# 差し替えて追随を検査するため。

nippo_vault() {
  echo "${NIPPO_VAULT:-$HOME/Obsidian}"
}

nippo_root() {
  echo "${NIPPO_DIR:-$(nippo_vault)/02_Daily}"
}

# nippo_resolve_date [YYYY-MM-DD]
# 引数が空か未指定なら本日。7 skill にコピペされていた既定値解決を1本にする。
nippo_resolve_date() {
  local arg="${1:-}"
  if [[ -n "$arg" ]]; then
    echo "$arg"
  else
    date +%Y-%m-%d
  fi
}

# nippo_daily_dir <YYYY-MM-DD>
# 引数の日付は現構造では使わない（種別 + 年/月へ移行する際に使う）
nippo_daily_dir() {
  nippo_root
}

# nippo_daily_file <YYYY-MM-DD>
nippo_daily_file() {
  echo "$(nippo_daily_dir "$1")/nippo.$1.md"
}

# nippo_weekly_dir <YYYY-Wnn>
# 引数の週は現構造では使わない（年で畳む際に使う）
nippo_weekly_dir() {
  nippo_root
}

# nippo_weekly_file <YYYY-Wnn>
nippo_weekly_file() {
  echo "$(nippo_weekly_dir "$1")/nippo-weekly.$1.md"
}

nippo_goals_file() {
  echo "$(nippo_root)/nippo-goals.md"
}
