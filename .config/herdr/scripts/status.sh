#!/bin/bash
# herdr の ui.tab_bar_right に出すマシンリソースの1行ステータス。
#
#   CPU 12% · MEM 5.9/11.7G · LA 1.06
#
# 設計上の決めごと:
#   ・herdr は「成功した出力の最終行」だけを使うので、出力は必ず1行に閉じる。
#     読めない項目は欄ごと落として exit 0 で返す。1項目のためにステータス全体が
#     消えるほうが害が大きい。
#   ・**herdr に出すときは着色しない（既定 never）。** herdr のタブ行は受け取った文字列の
#     ESC バイトだけを落とし、残りを可視文字として描画する。`\033[38;5;208m` を出すと
#     `[38;5;208m` がそのまま表示される（入れ子 herdr を pane read して実測）。
#     タブ行の文字色は theme の overlay1 トークンで一括指定するもので、項目ごとには変えられない。
#     閾値による色分けは残してあるが、これはターミナルで直接叩いたときのためのもの。
#   ・**外部コマンドを1つも呼ばない。** date / awk / grep / cut を素直に使った版は
#     実測 53ms/回 かかり、1秒間隔だと1コアの5%を常時食う。bash の組み込みだけに
#     寄せて 3ms 程度に落としている。ここが唯一の速度要件で、可読性より優先する。
#   ・CPU% は /proc/stat の累積値なので、前回値をキャッシュして差分で出す。
#     sleep を挟んで2点取る方式は毎回待つことになり 1秒間隔と相性が悪い。
#   ・前回値が無い初回だけは「起動からの平均」で埋める。次の呼び出しから瞬間値になる。
#     空欄にすると herdr 起動直後だけ欄が欠けて幅が動く。
set -uo pipefail

STAT_FILE="${HERDR_STATUS_STAT:-/proc/stat}"
MEMINFO_FILE="${HERDR_STATUS_MEMINFO:-/proc/meminfo}"
LOADAVG_FILE="${HERDR_STATUS_LOADAVG:-/proc/loadavg}"
CACHE_FILE="${HERDR_STATUS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/herdr-status/cpu}"
COLOR="${HERDR_STATUS_COLOR:-never}"
SEP=" · "

OUT=""
SGR=""

# 「緑 / 黄 / 赤」を整数の閾値で選ぶ。小数は呼び出し側でスケールして渡す。
set_sgr() {
  if [ "$1" -ge "$3" ]; then
    SGR="1;31"
  elif [ "$1" -ge "$2" ]; then
    SGR="1;33"
  else
    SGR="1;32"
  fi
}

# ラベルは素のまま、値だけを着色する。色が意味を持つ場所を値に限るため。
add() {
  local label="$1" value="$2" sgr="$3" piece
  if [ "$COLOR" = "never" ]; then
    piece="$label$value"
  else
    piece="$label"$'\033'"[${sgr}m${value}"$'\033'"[0m"
  fi
  if [ -n "$OUT" ]; then
    OUT="$OUT$SEP$piece"
  else
    OUT="$piece"
  fi
}

# 1/10 単位の整数を「5.9」の形にする（printf の %f を避けて fork を減らす）
tenths() {
  printf -v TENTHS '%s.%s' "$(($1 / 10))" "$(($1 % 10))"
}

# --- CPU ------------------------------------------------------------------
# 集計行から累積 total と累積 busy を出す。busy は total から idle(4) と iowait(5) を除く。
# あわせて cpuN 行を数えて論理コア数を得る（LA の閾値に使う。nproc を呼ばずに済ませる）。
cpu_total=0
cpu_busy=0
cpu_ok=0
cores=0
if [ -r "$STAT_FILE" ]; then
  while read -r name rest; do
    case "$name" in
      cpu)
        total=0
        idle=0
        index=0
        # shellcheck disable=SC2086 # 空白区切りのフィールドに分解したい
        set -- $rest
        for field in "$@"; do
          case "$field" in
            '' | *[!0-9]*)
              total=0
              break
              ;;
          esac
          total=$((total + field))
          index=$((index + 1))
          if [ "$index" -eq 4 ] || [ "$index" -eq 5 ]; then
            idle=$((idle + field))
          fi
        done
        if [ "$index" -ge 5 ] && [ "$total" -gt 0 ]; then
          cpu_total="$total"
          cpu_busy=$((total - idle))
          cpu_ok=1
        fi
        ;;
      cpu[0-9]*) cores=$((cores + 1)) ;;
      # cpu 系の行は先頭にまとまっているので、そこを抜けたら読むのをやめる
      *) break ;;
    esac
  done <"$STAT_FILE"
fi

if [ "$cpu_ok" -eq 1 ]; then
  prev_total=""
  prev_busy=""
  if [ -r "$CACHE_FILE" ]; then
    read -r prev_total prev_busy _ <"$CACHE_FILE" || true
  fi
  case "${prev_total:-x}${prev_busy:-x}" in
    *[!0-9]*)
      prev_total=""
      ;;
  esac

  cache_dir="${CACHE_FILE%/*}"
  [ -d "$cache_dir" ] || mkdir -p "$cache_dir" 2>/dev/null
  printf '%s %s\n' "$cpu_total" "$cpu_busy" >"$CACHE_FILE" 2>/dev/null || true

  if [ -n "$prev_total" ] && [ "$cpu_total" -gt "$prev_total" ]; then
    d_total=$((cpu_total - prev_total))
    d_busy=$((cpu_busy - prev_busy))
  else
    # 初回・キャッシュ破損・カウンタ巻き戻しは起動からの平均で埋める
    d_total="$cpu_total"
    d_busy="$cpu_busy"
  fi
  [ "$d_busy" -ge 0 ] || d_busy=0
  if [ "$d_total" -gt 0 ]; then
    pct=$(((100 * d_busy + d_total / 2) / d_total))
    set_sgr "$pct" 60 85
    add "CPU " "$pct%" "$SGR"
  fi
fi

# --- メモリ ---------------------------------------------------------------
mem_total=0
mem_avail=""
if [ -r "$MEMINFO_FILE" ]; then
  while read -r key value _; do
    case "$key" in
      MemTotal:) mem_total="$value" ;;
      MemAvailable:)
        mem_avail="$value"
        break
        ;;
    esac
  done <"$MEMINFO_FILE"
fi
case "${mem_total:-x}${mem_avail:-x}" in
  *[!0-9]*) mem_total=0 ;;
esac
if [ "$mem_total" -gt 0 ]; then
  used=$((mem_total - mem_avail))
  [ "$used" -ge 0 ] || used=0
  # kB → GiB を1/10単位の整数で四捨五入する（1048576 = 1GiB/kB, 524288 はその半分）
  tenths $(((used * 10 + 524288) / 1048576))
  used_g="$TENTHS"
  tenths $(((mem_total * 10 + 524288) / 1048576))
  total_g="$TENTHS"
  set_sgr $((used * 100 / mem_total)) 70 85
  add "MEM " "$used_g/${total_g}G" "$SGR"
fi

# --- ロードアベレージ -----------------------------------------------------
la=""
if [ -r "$LOADAVG_FILE" ]; then
  read -r la _ <"$LOADAVG_FILE" || true
fi
case "${la:-x}" in
  '' | *[!0-9.]*) la="" ;;
esac
if [ -n "$la" ]; then
  n="${HERDR_STATUS_NPROC:-$cores}"
  case "${n:-x}" in
    '' | 0 | *[!0-9]*) n=1 ;;
  esac
  # 1コアあたりの負荷で色を決める。0.5/core で黄、0.9/core で赤。
  # 小数を扱わないよう 1/100 単位の整数に直して比較する。
  int="${la%%.*}"
  frac="${la#*.}00"
  [ "$int" = "$la" ] && frac="000"
  set_sgr $((10#${int:-0} * 100 + 10#${frac:0:2})) $((n * 50)) $((n * 90))
  add "LA " "$la" "$SGR"
fi

printf '%s' "$OUT"
exit 0
