#!/bin/bash
# herdr nvim registryは復元可能なinteractive processだけを1 process=1 recordで残す。
# 今回見つかったfile引数の欠落と、同一paneのclean exit競合を検知する回帰test。
#
# ci-skip: 実nvim設定とplugin導入済み環境が要る
set -uo pipefail

ROOT=$(mktemp -d)
STATE="$ROOT/state"
CACHE="$ROOT/cache"
SESSIONS="$ROOT/sessions"
mkdir -p "$STATE" "$CACHE" "$SESSIONS"
export NVIM_LOG_FILE="$ROOT/nvim.log"
trap 'jobs -pr | xargs -r kill 2>/dev/null; rm -rf "$ROOT"' EXIT

PASS=0
FAIL=0

ok() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}
ng() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}

start_nvim() {
  local pane="$1" sock="$2"
  shift 2
  (cd "$ROOT" && exec env \
    XDG_STATE_HOME="$STATE" XDG_CACHE_HOME="$CACHE" \
    MY_AUTOSESSION_ROOT_DIR="$SESSIONS" HERDR_PANE_ID="$pane" \
    HERDR_SOCKET_PATH="$ROOT/herdr.sock" HERDR_BIN_PATH="${TEST_HERDR_BIN:-/bin/false}" \
    HERDR_NVIM_REGISTRY_TEST=1 nvim --headless --listen "$sock" "$@") >/dev/null 2>&1 &
  NVIM_PID=$!
  for _ in $(seq 1 60); do
    nvim --server "$sock" --remote-expr '1' >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

wait_for_markers() {
  local want="$1" deadline=$((SECONDS + 10))
  while ((SECONDS < deadline)); do
    [[ $(find "$STATE/herdr-nvim" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l) -eq "$want" ]] && return 0
    sleep 0.1
  done
  return 1
}

wait_for_pane() {
  local want="$1" deadline=$((SECONDS + 10)) record
  while ((SECONDS < deadline)); do
    record=$(find "$STATE/herdr-nvim" -maxdepth 1 -name '*.json' -print -quit 2>/dev/null)
    [[ -n "$record" ]] && [[ "$(jq -r '.pane_id' "$record")" == "$want" ]] && return 0
    sleep 0.1
  done
  return 1
}

echo "test: file引数を復元recordへ保持する"
touch "$ROOT/a file.txt"
start_nvim w1:p1 "$ROOT/file.sock" "a file.txt" || {
  ng "nvim起動"
  exit 1
}
file_pid=$NVIM_PID
if wait_for_markers 1; then
  record=$(find "$STATE/herdr-nvim" -maxdepth 1 -name '*.json' -print -quit)
  if jq -e '.version == 2 and .kind == "files" and .args == ["a file.txt"] and .pane_id == "w1:p1"' "$record" >/dev/null; then
    ok "file引数付きprocessをその引数で記録する"
  else
    ng "file引数のrecordが不正"
  fi
else
  ng "recordが作られない"
fi
kill -TERM "$file_pid" 2>/dev/null
wait "$file_pid" 2>/dev/null

echo "test: pane move後のpublic IDへ追随する"
rm -f "$STATE/herdr-nvim"/*.json
FAKE_HERDR="$ROOT/herdr-fake"
printf '%s\n' '#!/bin/sh' \
  "printf '%s\\n' '{\"result\":{\"pane\":{\"pane_id\":\"w2:p9\"}}}'" >"$FAKE_HERDR"
chmod +x "$FAKE_HERDR"
TEST_HERDR_BIN="$FAKE_HERDR" start_nvim w1:p9 "$ROOT/move.sock" || {
  ng "move用nvim起動"
  exit 1
}
move_pid=$NVIM_PID
if wait_for_pane w2:p9; then
  ok "現在pane IDでrecordを書き直す"
else
  ng "pane moveへ追随しない"
fi
kill -TERM "$move_pid" 2>/dev/null
wait "$move_pid" 2>/dev/null

echo "test: 同一paneのclean exitは他processのrecordを消さない"
rm -f "$STATE/herdr-nvim"/*.json
start_nvim w1:p2 "$ROOT/one.sock" || {
  ng "1本目のnvim起動"
  exit 1
}
one_pid=$NVIM_PID
start_nvim w1:p2 "$ROOT/two.sock" || {
  ng "2本目のnvim起動"
  exit 1
}
two_pid=$NVIM_PID
wait_for_markers 2 || ng "2process分のrecordができる"
nvim --server "$ROOT/one.sock" --remote-send ':qa!<CR>' >/dev/null 2>&1
wait "$one_pid" 2>/dev/null
if wait_for_markers 1 && kill -0 "$two_pid" 2>/dev/null; then
  ok "終了したownerのrecordだけを削除する"
else
  ng "別processのrecordまで消えた"
fi
kill -TERM "$two_pid" 2>/dev/null
wait "$two_pid" 2>/dev/null

echo "test: 通常headless processは記録しない"
rm -f "$STATE/herdr-nvim"/*.json
(cd "$ROOT" && env XDG_STATE_HOME="$STATE" XDG_CACHE_HOME="$CACHE" \
  MY_AUTOSESSION_ROOT_DIR="$SESSIONS" HERDR_PANE_ID=w1:p3 \
  HERDR_SOCKET_PATH="$ROOT/herdr.sock" nvim --headless -c 'qa!') >/dev/null 2>&1
if [[ -z "$(find "$STATE/herdr-nvim" -maxdepth 1 -name '*.json' -print -quit 2>/dev/null)" ]]; then
  ok "headless utility起動を復元対象にしない"
else
  ng "headless utilityが記録された"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
