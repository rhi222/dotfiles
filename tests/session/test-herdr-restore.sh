#!/bin/bash
# herdr復元は使用中paneと取得失敗を破壊せず、起動確認後だけ完了に数える。
# status・process判定・表示整形の契約を外部herdrなしで検査する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/internal/session/restore.sh"

if [[ ! -f "$LIB" ]]; then
  echo "ERROR: $LIB が存在しません"
  exit 1
fi

# shellcheck source=../../internal/session/restore.sh
source "$LIB"

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""

setup() {
  TEST_DIR=$(mktemp -d)
}

teardown() {
  rm -rf "$TEST_DIR"
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected: [$expected]"
    echo "    actual  : [$actual]"
  fi
}

assert_ok() {
  local name="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@"; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (真であるべき)"
  fi
}

assert_ng() {
  local name="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (偽であるべき)"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  fi
}

echo "test: pane_is_idle"
IDLE='{"result":{"process_info":{"foreground_processes":[{"cmdline":"/usr/bin/fish","pid":23983}],"shell_pid":23983}}}'
BUSY='{"result":{"process_info":{"foreground_processes":[{"cmdline":"nvim","pid":24497}],"shell_pid":23986}}}'
EMPTY='{"result":{}}'
assert_ok "素のシェルは idle" herdr_restore_pane_is_idle "$IDLE"
assert_ng "何か走っていれば idle でない" herdr_restore_pane_is_idle "$BUSY"
assert_ng "情報が取れなければ idle でない" herdr_restore_pane_is_idle "$EMPTY"
assert_ok "nvimを起動確認できる" herdr_restore_pane_is_nvim "$BUSY"
assert_ng "shellをnvimと誤認しない" herdr_restore_pane_is_nvim "$IDLE"

echo "test: format_duration"
assert_eq "60秒未満は秒だけ" "45秒" "$(herdr_restore_format_duration 45)"
assert_eq "0秒" "0秒" "$(herdr_restore_format_duration 0)"
assert_eq "分と秒" "3分18秒" "$(herdr_restore_format_duration 198)"
assert_eq "ちょうど分なら秒を出さない" "3分" "$(herdr_restore_format_duration 180)"
assert_eq "時間と分" "1時間2分" "$(herdr_restore_format_duration 3723)"
assert_eq "ちょうど時間なら分を出さない" "2時間" "$(herdr_restore_format_duration 7200)"
assert_eq "数値でなければ0秒" "0秒" "$(herdr_restore_format_duration '')"

echo "test: counts_summary"
assert_eq "スキップなし" "nvim 4/10" "$(herdr_restore_counts_summary 4 10 0)"
assert_eq "スキップあり" "nvim 8/10 (2件は使用中でスキップ)" "$(herdr_restore_counts_summary 8 10 2)"

echo "test: status の読み書き"
setup
STATUS="$TEST_DIR/herdr-restore.status"
herdr_restore_status_init "$STATUS" 12345 1000 10
assert_eq "state は running" "running" "$(herdr_restore_status_get "$STATUS" state)"
assert_eq "pid を持つ" "12345" "$(herdr_restore_status_get "$STATUS" pid)"
assert_eq "started_at を持つ" "1000" "$(herdr_restore_status_get "$STATUS" started_at)"
assert_eq "total は引数どおり" "10" "$(herdr_restore_status_get "$STATUS" nvim_total)"
assert_eq "done は0から" "0" "$(herdr_restore_status_get "$STATUS" nvim_done)"
assert_eq "finished_at は空" "" "$(herdr_restore_status_get "$STATUS" finished_at)"
herdr_restore_status_bump "$STATUS" nvim_done
herdr_restore_status_bump "$STATUS" nvim_done
assert_eq "bump で1ずつ増える" "2" "$(herdr_restore_status_get "$STATUS" nvim_done)"
herdr_restore_status_set "$STATUS" nvim_skipped 3
assert_eq "set で上書きできる" "3" "$(herdr_restore_status_get "$STATUS" nvim_skipped)"
assert_eq "他のキーは壊れない" "10" "$(herdr_restore_status_get "$STATUS" nvim_total)"
herdr_restore_status_finish "$STATUS" "done" 1198 ""
assert_eq "finish で state が変わる" "done" "$(herdr_restore_status_get "$STATUS" state)"
assert_eq "finish で finished_at が入る" "1198" "$(herdr_restore_status_get "$STATUS" finished_at)"
assert_eq "無いキーは空" "" "$(herdr_restore_status_get "$STATUS" nosuchkey)"
assert_eq "ファイルが無ければ空" "" "$(herdr_restore_status_get "$TEST_DIR/nope" state)"
teardown

echo "test: status_render"
setup
STATUS="$TEST_DIR/herdr-restore.status"
assert_eq "ファイルが無ければ記録なし" "herdr 復元: 記録なし" "$(herdr_restore_status_render "$TEST_DIR/nope" 1000 0)"
herdr_restore_status_init "$STATUS" 12345 1000 10
herdr_restore_status_set "$STATUS" nvim_done 4
assert_eq "実行中" \
  "herdr 復元: 実行中  nvim 4/10  経過 1分23秒" \
  "$(herdr_restore_status_render "$STATUS" 1083 1)"
assert_eq "running のまま pid が死んでいれば中断" \
  "herdr 復元: 中断  nvim 4/10  開始から 1分23秒 (プロセス不在)" \
  "$(herdr_restore_status_render "$STATUS" 1083 0)"
herdr_restore_status_set "$STATUS" nvim_done 9
herdr_restore_status_set "$STATUS" nvim_skipped 1
herdr_restore_status_finish "$STATUS" "done" 1198 ""
assert_eq "完了" \
  "herdr 復元: 完了  nvim 9/10 (1件は使用中でスキップ)  所要 3分18秒" \
  "$(herdr_restore_status_render "$STATUS" 2000 0)"
herdr_restore_status_finish "$STATUS" failed 1002 pane-list
assert_eq "失敗は理由だけを出す" \
  "herdr 復元: 失敗  ペイン一覧を取得できませんでした" \
  "$(herdr_restore_status_render "$STATUS" 2000 0)"
teardown

echo "test: toast の本文"
assert_eq "開始" "nvim 10件を順に起動します" "$(herdr_restore_toast_start_body 10)"
assert_eq "完了" \
  "nvim 9/10 (1件は使用中でスキップ) / 所要 3分18秒" \
  "$(herdr_restore_toast_done_body 9 10 1 198)"

echo ""
echo "TOTAL=$TOTAL PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
