#!/bin/bash
# herdr復元は生存paneだけを安全な順序で計画し、使用中paneと取得失敗を破壊しない。
# marker・status・表示整形の契約を外部herdrなしで検査する。
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
NVIM_DIR=""
CLAUDE_DIR=""
ALIVE=""

setup() {
  TEST_DIR=$(mktemp -d)
  NVIM_DIR="$TEST_DIR/herdr-nvim"
  CLAUDE_DIR="$TEST_DIR/herdr-claude"
  ALIVE="$TEST_DIR/alive"
  mkdir -p "$NVIM_DIR" "$CLAUDE_DIR"
  : >"$ALIVE"
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

nvim_marker() { printf '/tmp/proj\n' >"$NVIM_DIR/$1"; }
# 既定の cwd は実在しないパスにする。実在すると cd が前置され、cwd を
# 見ないケースの検証にならない。
claude_marker() { claude_marker_at "$1" "$2" "$3" "/nonexistent/herdr-test"; }
claude_marker_at() { printf '%s\n%s\n%s\n' "$2" "$4" "$3" >"$CLAUDE_DIR/$1"; }

echo "test: workspace_of"
assert_eq "w5:p29 -> w5" "w5" "$(herdr_restore_workspace_of w5:p29)"
assert_eq "w6:p8V -> w6" "w6" "$(herdr_restore_workspace_of w6:p8V)"

echo "test: claude_command"
setup
touch "$TEST_DIR/t.jsonl"
claude_marker "w5:p1" "sess-1" "$TEST_DIR/t.jsonl"
assert_eq "transcript があれば resume" "claude --resume sess-1" "$(herdr_restore_claude_command "$CLAUDE_DIR/w5:p1")"
claude_marker "w5:p2" "sess-2" "$TEST_DIR/missing.jsonl"
assert_eq "transcript が無ければ素の claude" "claude" "$(herdr_restore_claude_command "$CLAUDE_DIR/w5:p2")"
claude_marker "w5:p3" "" ""
assert_eq "session_id が空なら素の claude" "claude" "$(herdr_restore_claude_command "$CLAUDE_DIR/w5:p3")"
teardown

# claude が自分で移した cwd（worktree など）はシェルに残らないため herdr の
# session.json では復元できない。marker に記録した cwd を使って戻す。
echo "test: claude_command は marker の cwd へ戻す"
setup
touch "$TEST_DIR/t.jsonl"
mkdir -p "$TEST_DIR/wt"
claude_marker_at "w5:p4" "sess-4" "$TEST_DIR/t.jsonl" "$TEST_DIR/wt"
assert_eq "cwd が実在すれば cd を前置する" \
  "cd $TEST_DIR/wt && claude --resume sess-4" \
  "$(herdr_restore_claude_command "$CLAUDE_DIR/w5:p4")"

# worktree が消えていても claude 自体は立てたい。&& で止めない。
claude_marker_at "w5:p5" "sess-5" "$TEST_DIR/t.jsonl" "$TEST_DIR/gone"
assert_eq "cwd が消えていれば cd しない" \
  "claude --resume sess-5" \
  "$(herdr_restore_claude_command "$CLAUDE_DIR/w5:p5")"

claude_marker_at "w5:p6" "" "" "$TEST_DIR/wt"
assert_eq "resume できなくても cd はする" \
  "cd $TEST_DIR/wt && claude" \
  "$(herdr_restore_claude_command "$CLAUDE_DIR/w5:p6")"

claude_marker_at "w5:p7" "sess-7" "$TEST_DIR/t.jsonl" ""
assert_eq "cwd が空なら cd しない" \
  "claude --resume sess-7" \
  "$(herdr_restore_claude_command "$CLAUDE_DIR/w5:p7")"
teardown

echo "test: plan の並び順"
setup
touch "$TEST_DIR/t.jsonl"
printf 'w5:p1\nw5:p2\nw6:p1\nw6:p2\n' >"$ALIVE"
nvim_marker "w5:p1"
nvim_marker "w6:p1"
claude_marker "w5:p2" "sess-a" "$TEST_DIR/t.jsonl"
claude_marker "w6:p2" "sess-b" "$TEST_DIR/t.jsonl"
EXPECTED=$(printf 'nvim\tw5:p1\tnvim\nnvim\tw6:p1\tnvim\nclaude\tw5:p2\tclaude --resume sess-a\nclaude\tw6:p2\tclaude --resume sess-b')
assert_eq "nvim が先、各種別内はフォーカス中 workspace が先" "$EXPECTED" "$(herdr_restore_plan "$NVIM_DIR" "$CLAUDE_DIR" "$ALIVE" "w5")"
teardown

echo "test: 死んだペインは plan に入らない"
setup
printf 'w5:p1\n' >"$ALIVE"
nvim_marker "w5:p1"
nvim_marker "w5:p99"
assert_eq "生存ペインだけ" "$(printf 'nvim\tw5:p1\tnvim')" "$(herdr_restore_plan "$NVIM_DIR" "$CLAUDE_DIR" "$ALIVE" "w5")"
teardown

echo "test: prune_markers"
setup
printf 'w5:p1\n' >"$ALIVE"
nvim_marker "w5:p1"
nvim_marker "w5:p99"
herdr_restore_prune_markers "$NVIM_DIR" "$ALIVE"
assert_eq "生存ペインのマーカーは残る" "present" "$([[ -f "$NVIM_DIR/w5:p1" ]] && echo present || echo absent)"
assert_eq "死んだペインのマーカーは消える" "absent" "$([[ -f "$NVIM_DIR/w5:p99" ]] && echo present || echo absent)"
teardown

echo "test: alive が空なら何も消さない"
setup
: >"$ALIVE"
nvim_marker "w5:p1"
herdr_restore_prune_markers "$NVIM_DIR" "$ALIVE"
assert_eq "取得失敗時はマーカーを保持する" "present" "$([[ -f "$NVIM_DIR/w5:p1" ]] && echo present || echo absent)"
teardown

echo "test: pane_is_idle"
IDLE='{"result":{"process_info":{"foreground_processes":[{"cmdline":"/usr/bin/fish","pid":23983}],"shell_pid":23983}}}'
BUSY='{"result":{"process_info":{"foreground_processes":[{"cmdline":"nvim","pid":24497}],"shell_pid":23986}}}'
EMPTY='{"result":{}}'
assert_ok "素のシェルは idle" herdr_restore_pane_is_idle "$IDLE"
assert_ng "何か走っていれば idle でない" herdr_restore_pane_is_idle "$BUSY"
assert_ng "情報が取れなければ idle でない" herdr_restore_pane_is_idle "$EMPTY"

echo "test: format_duration"
assert_eq "60秒未満は秒だけ" "45秒" "$(herdr_restore_format_duration 45)"
assert_eq "0秒" "0秒" "$(herdr_restore_format_duration 0)"
assert_eq "分と秒" "3分18秒" "$(herdr_restore_format_duration 198)"
assert_eq "ちょうど分なら秒を出さない" "3分" "$(herdr_restore_format_duration 180)"
assert_eq "時間と分" "1時間2分" "$(herdr_restore_format_duration 3723)"
assert_eq "ちょうど時間なら分を出さない" "2時間" "$(herdr_restore_format_duration 7200)"
assert_eq "数値でなければ0秒" "0秒" "$(herdr_restore_format_duration '')"

echo "test: counts_summary"
assert_eq "スキップなし" "nvim 4/10, claude 0/5" "$(herdr_restore_counts_summary 4 10 0 0 5 0)"
assert_eq "スキップあり" "nvim 10/10, claude 4/5 (1件は使用中でスキップ)" "$(herdr_restore_counts_summary 10 10 0 4 5 1)"
assert_eq "スキップは種別をまたいで合算する" "nvim 8/10, claude 3/5 (4件は使用中でスキップ)" "$(herdr_restore_counts_summary 8 10 2 3 5 2)"

echo "test: status の読み書き"
setup
STATUS="$TEST_DIR/herdr-restore.status"
herdr_restore_status_init "$STATUS" 12345 1000 10 5
assert_eq "state は running" "running" "$(herdr_restore_status_get "$STATUS" state)"
assert_eq "pid を持つ" "12345" "$(herdr_restore_status_get "$STATUS" pid)"
assert_eq "started_at を持つ" "1000" "$(herdr_restore_status_get "$STATUS" started_at)"
assert_eq "total は引数どおり" "10" "$(herdr_restore_status_get "$STATUS" nvim_total)"
assert_eq "done は0から" "0" "$(herdr_restore_status_get "$STATUS" nvim_done)"
assert_eq "finished_at は空" "" "$(herdr_restore_status_get "$STATUS" finished_at)"
herdr_restore_status_bump "$STATUS" nvim_done
herdr_restore_status_bump "$STATUS" nvim_done
assert_eq "bump で1ずつ増える" "2" "$(herdr_restore_status_get "$STATUS" nvim_done)"
herdr_restore_status_set "$STATUS" claude_skipped 3
assert_eq "set で上書きできる" "3" "$(herdr_restore_status_get "$STATUS" claude_skipped)"
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
herdr_restore_status_init "$STATUS" 12345 1000 10 5
herdr_restore_status_set "$STATUS" nvim_done 4
assert_eq "実行中" \
  "herdr 復元: 実行中  nvim 4/10, claude 0/5  経過 1分23秒" \
  "$(herdr_restore_status_render "$STATUS" 1083 1)"
assert_eq "running のまま pid が死んでいれば中断" \
  "herdr 復元: 中断  nvim 4/10, claude 0/5  開始から 1分23秒 (プロセス不在)" \
  "$(herdr_restore_status_render "$STATUS" 1083 0)"
herdr_restore_status_set "$STATUS" nvim_done 10
herdr_restore_status_set "$STATUS" claude_done 4
herdr_restore_status_set "$STATUS" claude_skipped 1
herdr_restore_status_finish "$STATUS" "done" 1198 ""
assert_eq "完了" \
  "herdr 復元: 完了  nvim 10/10, claude 4/5 (1件は使用中でスキップ)  所要 3分18秒" \
  "$(herdr_restore_status_render "$STATUS" 2000 0)"
herdr_restore_status_finish "$STATUS" failed 1002 pane-list
assert_eq "失敗は理由だけを出す" \
  "herdr 復元: 失敗  ペイン一覧を取得できませんでした" \
  "$(herdr_restore_status_render "$STATUS" 2000 0)"
teardown

echo "test: toast の本文"
assert_eq "開始" "nvim 10, claude 5 を順に起動します" "$(herdr_restore_toast_start_body 10 5)"
assert_eq "完了" \
  "nvim 10/10, claude 4/5 (1件は使用中でスキップ) / 所要 3分18秒" \
  "$(herdr_restore_toast_done_body 10 10 0 4 5 1 198)"

echo ""
echo "TOTAL=$TOTAL PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
