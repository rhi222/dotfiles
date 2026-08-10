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
