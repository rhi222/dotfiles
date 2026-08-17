#!/bin/bash
# cron から headless の Claude Code を呼ぶための共通関数。
#
# 使い方:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/cron-claude.sh"
#   cron_run_claude "日報仕上げ" "$TIMEOUT" "$CLAUDE_BIN" -p "$PROMPT" --allowedTools "$TOOLS"
#
# 必ず timeout を噛ませる。cron から起動する headless 実行は誰も見ていないので、
# ハングすると次の起動と重なったまま朝まで残る。
#
# set は宣言しない。source 元の設定を尊重する（他の lib と同じ方針）。

# cron_require_flag <フラグファイルのパス>
# 有効化フラグが無ければスクリプトごと静かに exit 0 する。
# cron ラッパーの「無効なら何も出さずに終わる」定型ガード。
# 条件に当たったら呼び出し元へ返さず終了させるので、呼び出しは1行で済む。
cron_require_flag() {
  local flag="$1"
  if [[ ! -f "$flag" ]]; then
    exit 0
  fi
}

# cron_weekday_only <force値>
# 土日（date +%u が 6,7）かつ force が "1" でなければ、スクリプトごと静かに exit 0 する。
# force に FORCE 環境変数の値を渡すと、テスト・手動実行で週末ガードを抜けられる。
cron_weekday_only() {
  local force="${1:-0}"
  local dow
  dow=$(date +%u)
  if [[ "$dow" -ge 6 && "$force" != "1" ]]; then
    exit 0
  fi
}

# cron_run_claude <ラベル> <制限秒> <claudeのパス> [claudeへの引数...]
# 戻り値: claude の終了コード。タイムアウトは 124
# 診断メッセージは stderr に出す（stdout は成果物のために空けておく）
cron_run_claude() {
  local label="$1" limit="$2" bin="$3"
  shift 3

  local rc=0
  # set -e 下でも自前で拾えるよう || で受ける
  timeout "$limit" "$bin" "$@" || rc=$?

  if [ "$rc" -eq 124 ]; then
    echo "$(date): ${label} がタイムアウトした（${limit}秒で打ち切り）" >&2
  elif [ "$rc" -ne 0 ]; then
    echo "$(date): ${label} が失敗した（exit ${rc}）" >&2
  fi
  return "$rc"
}
