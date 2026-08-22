#!/bin/bash
# .config/herdr/scripts/{clock,status}.sh のユニットテスト
#
# herdr の ui.tab_bar_right の command エントリは、コマンドの「成功した出力の最終行」
# だけをタブ行に出す。1秒間隔で叩かれるので、ここでは
#   ・時計とマシンリソースが別々の1行に収まること
#   ・/proc が読めない状況でも exit 0 して欄を落とすだけに留まること
#   ・CPU% がキャッシュとの差分から出ること（実機の負荷に依存しないこと）
# を検証する。/proc と キャッシュと現在時刻は環境変数で差し替える。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATUS_TARGET="$REPO_ROOT/.config/herdr/scripts/status.sh"
CLOCK_TARGET="$REPO_ROOT/.config/herdr/scripts/clock.sh"

for target in "$CLOCK_TARGET" "$STATUS_TARGET"; do
  if [[ ! -x "$target" ]]; then
    echo "ERROR: $target が実行可能ファイルとして存在しません"
    exit 1
  fi
done

PASS=0
FAIL=0
TOTAL=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

strip_ansi() {
  sed -e 's/\x1b\[[0-9;]*m//g'
}

ok() {
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

ng() {
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
  shift
  for line in "$@"; do
    echo "        $line"
  done
}

check_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    ok "$name"
  else
    ng "$name" "期待: [$expected]" "実際: [$actual]"
  fi
}

check_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$name"
  else
    ng "$name" "[$needle] を含むべき" "実際: [$haystack]"
  fi
}

check_not_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    ok "$name"
  else
    ng "$name" "[$needle] を含まないべき" "実際: [$haystack]"
  fi
}

# --- フィクスチャ ---------------------------------------------------------
# total=2000 / busy=600（user 600 + idle 1400）。前回スナップショットを
# total=1000 / busy=100 にすると、差分は total 1000 / busy 500 で 50% になる。
STAT="$WORK/stat"
printf 'cpu  600 0 0 1400 0 0 0 0 0 0\ncpu0 1 2 3 4 5 6 7 0 0 0\n' >"$STAT"

MEMINFO="$WORK/meminfo"
cat >"$MEMINFO" <<'EOF'
MemTotal:       12249204 kB
MemFree:         2000000 kB
MemAvailable:    6016960 kB
Buffers:          100000 kB
EOF

LOADAVG="$WORK/loadavg"
printf '1.06 0.91 1.13 2/822 402032\n' >"$LOADAVG"

CACHE="$WORK/cpu-snapshot"
seed_cache() { printf '1000 100\n' >"$CACHE"; }

# 2026-08-20 11:42:03 (木) を固定で渡す。TZ を明示して端末の設定に依存させない。
export TZ=Asia/Tokyo
EPOCH="$(date -d '2026-08-20 11:42:03' +%s)"

run_target() {
  env \
    HERDR_STATUS_STAT="$STAT" \
    HERDR_STATUS_MEMINFO="$MEMINFO" \
    HERDR_STATUS_LOADAVG="$LOADAVG" \
    HERDR_STATUS_CACHE="$CACHE" \
    HERDR_STATUS_NPROC=6 \
    HERDR_STATUS_COLOR="${HERDR_STATUS_COLOR:-never}" \
    "$STATUS_TARGET"
}

run_clock() {
  env HERDR_CLOCK_EPOCH="${HERDR_CLOCK_EPOCH:-$EPOCH}" "$CLOCK_TARGET"
}

echo "=== 通常系 ==="
seed_cache
clock_out="$(run_clock)"
out="$(run_target)"
rc=$?
check_eq "終了コードは0" "0" "$rc"
check_eq "1行にまとまる" "1" "$(printf '%s' "$out" | grep -c '' || true)"
check_eq "時計はリソースと分離して出す" "8/20 Thu 11:42:03" "$clock_out"
check_eq "CPU・MEM・LA は区切って並ぶ" \
  "CPU 50% · MEM 5.9/11.7G · LA 1.06" \
  "$(printf '%s' "$out" | strip_ansi)"

echo "=== 月日はゼロ埋めしない ==="
seed_cache
out="$(HERDR_CLOCK_EPOCH="$(date -d '2026-01-05 09:03:04' +%s)" run_clock | strip_ansi)"
check_contains "1桁の月日は 1/5 と出す" "1/5 Mon 09:03:04" "$out"

echo "=== 曜日は %a ではなく番号から当てる ==="
# 7日連続で回して曜日名の並びを検査する。LC_ALL を変えても表記が動かないこと。
expected_dow=(Thu Fri Sat Sun Mon Tue Wed)
for i in 0 1 2 3 4 5 6; do
  seed_cache
  day="$((20 + i))"
  ep="$(date -d "2026-08-$day 11:42:03" +%s)"
  out="$(LC_ALL=C HERDR_CLOCK_EPOCH="$ep" run_clock | strip_ansi)"
  check_contains "8/$day は ${expected_dow[$i]}" "8/$day ${expected_dow[$i]} " "$out"
done

echo "=== CPU はスナップショット差分で出す ==="
seed_cache
printf 'cpu  1100 0 0 1900 0 0 0 0 0 0\n' >"$STAT" # total 3000 / busy 1100
out="$(run_target | strip_ansi)"
check_contains "delta total 2000 / busy 1000 なら 50%" "CPU 50%" "$out"
printf 'cpu  600 0 0 1400 0 0 0 0 0 0\ncpu0 1 2 3 4 5 6 7 0 0 0\n' >"$STAT"

echo "=== スナップショットを次回のために書き戻す ==="
seed_cache
run_target >/dev/null
check_eq "実行後のスナップショットは今回値" "2000 600" "$(cat "$CACHE")"

echo "=== 初回（スナップショット無し）でも欄を落とさない ==="
rm -f "$CACHE"
out="$(run_target | strip_ansi)"
rc=$?
check_eq "初回も exit 0" "0" "$rc"
check_contains "初回も CPU 欄が埋まる" "CPU " "$out"
check_not_contains "初回に CPU --% を出さない" "CPU --" "$out"

echo "=== 閾値で色を変える ==="
seed_cache
out="$(HERDR_STATUS_COLOR=always run_target)"
check_contains "color=always なら ANSI を含む" $'\033[' "$out"
out="$(HERDR_STATUS_COLOR=never run_target)"
check_not_contains "color=never なら ANSI を含まない" $'\033[' "$out"

seed_cache
printf '5.90 5.00 4.00 2/822 402032\n' >"$LOADAVG" # nproc 6 に対して高負荷
out="$(HERDR_STATUS_COLOR=always run_target)"
check_contains "高負荷の LA は赤(31)で出す" $'\033[1;31m5.90' "$out"
printf '0.30 0.20 0.10 2/822 402032\n' >"$LOADAVG"
out="$(HERDR_STATUS_COLOR=always run_target)"
check_contains "低負荷の LA は緑(32)で出す" $'\033[1;32m0.30' "$out"
printf '1.06 0.91 1.13 2/822 402032\n' >"$LOADAVG"

echo "=== /proc が読めなくても壊さない ==="
seed_cache
out="$(env \
  HERDR_STATUS_STAT="$WORK/none" \
  HERDR_STATUS_MEMINFO="$WORK/none" \
  HERDR_STATUS_LOADAVG="$WORK/none" \
  HERDR_STATUS_CACHE="$CACHE" \
  HERDR_STATUS_COLOR=never \
  "$STATUS_TARGET" 2>/dev/null)"
rc=$?
check_eq "読めなくても exit 0" "0" "$rc"
check_eq "読めないリソースは空欄にする" "" "$(printf '%s' "$out" | strip_ansi)"

echo "=== 壊れた入力を弾く ==="
seed_cache
printf 'cpu  x y z\n' >"$STAT"
out="$(run_target | strip_ansi)"
rc=$?
check_eq "数値でない /proc/stat でも exit 0" "0" "$rc"
check_not_contains "CPU 欄を無理に出さない" "CPU " "$out"
printf 'cpu  600 0 0 1400 0 0 0 0 0 0\ncpu0 1 2 3 4 5 6 7 0 0 0\n' >"$STAT"

seed_cache
printf 'garbage\n' >"$CACHE"
out="$(run_target | strip_ansi)"
rc=$?
check_eq "壊れたスナップショットでも exit 0" "0" "$rc"
check_contains "壊れたスナップショットは取り直す" "CPU " "$out"

echo "=== 出力に改行を含めない ==="
seed_cache
lines="$(run_target | wc -l)"
if [[ "$lines" -le 1 ]]; then
  ok "改行を含まない"
else
  ng "改行を含まない" "実際: ${lines}行"
fi

echo ""
echo "================================"
echo "合計: $TOTAL / PASS: $PASS / FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
