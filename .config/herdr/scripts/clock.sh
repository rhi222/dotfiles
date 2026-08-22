#!/bin/bash
# herdr の ui.tab_bar_right に出す時計。
#
#   8/20 Thu 12:09:33
#
# native の datetime エントリは更新間隔を指定できないため、秒を表示する時計は
# interval_seconds = 1 の command として独立させる。曜日はロケールで幅が変わる
# %a を避け、%w（番号）から固定の英語略称へ変換する。
set -uo pipefail

CLOCK=""
printf -v CLOCK '%(%w|%-m/%-d|%H:%M:%S)T' "${HERDR_CLOCK_EPOCH:--1}" 2>/dev/null || CLOCK=""
if [ -n "$CLOCK" ]; then
  DOW_NAMES=(Sun Mon Tue Wed Thu Fri Sat)
  dow="${CLOCK%%|*}"
  clock_rest="${CLOCK#*|}"
  md="${clock_rest%%|*}"
  hms="${clock_rest#*|}"
  case "$dow" in
    [0-6]) printf '%s' "$md ${DOW_NAMES[$dow]} $hms" ;;
    *) printf '%s' "$md $hms" ;;
  esac
fi

exit 0
