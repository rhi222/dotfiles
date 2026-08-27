#!/bin/bash
# herdr の ui.tab_bar_right（command エントリ2本目）: AI agent のレート上限。
#
#   CC s45% w50% f29% · CX s30% w2%
#   CC s45% w50% f29% · CXd s30% w2% · CXo s7% w12%  # Codex override設定時
#
# ロジックは全部 dotctl agent-usage 側にある（JSON と複数状態の集約は Go に
# 置く repo の方針）。ここは「dotctl が無い環境で欄ごと落とす」だけの薄い皮。
# status.sh と違い 60秒間隔なので、Go バイナリ起動（数ms）は許容範囲。
set -uo pipefail

DOTCTL="${HERDR_USAGE_DOTCTL:-${HOME:-}/.local/bin/dotctl}"
[ -x "$DOTCTL" ] || exit 0
exec "$DOTCTL" agent-usage line
