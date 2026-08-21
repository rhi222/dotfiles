#!/bin/bash
# .config/herdr/scripts/tab-switch.sh のユニットテスト
#
# herdr の keys.command popup から呼ばれ、fzf で tab を選んで `herdr tab focus` する。
# 実 herdr サーバーを立てずに検証するため、`herdr` と `fzf` を PATH 前方のスタブに
# 差し替える。スタブは受け取った引数と stdin をファイルに残すので、
#   ・表示列に何を出しているか
#   ・fzf の選択結果から tab_id を取り出して focus に渡せているか
#   ・キャンセル・0件・欠損フィールドで余計なことをしないか
# を外から観測できる。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET="$REPO_ROOT/.config/herdr/scripts/tab-switch.sh"

if [[ ! -x "$TARGET" ]]; then
  echo "ERROR: $TARGET が実行可能ファイルとして存在しません"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq が必要です"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"
mkdir -p "$BIN"

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

# --- スタブ -----------------------------------------------------------------
# herdr スタブ: `tab list` / `workspace list` は $WORK 配下の JSON を返す。
# `tab focus <id>` は引数を focus.log に残す。未知のサブコマンドは失敗させる
# （本番で別の呼び方に変えたらテストが気付くようにする）。
cat >"$BIN/herdr" <<'EOF'
#!/bin/bash
case "$1 ${2:-}" in
  "tab list") cat "$STUB_TAB_JSON" ;;
  "workspace list") cat "$STUB_WS_JSON" ;;
  "tab focus")
    printf '%s\n' "${3:-}" >>"$STUB_DIR/focus.log"
    ;;
  *)
    printf 'unexpected herdr invocation: %s\n' "$*" >>"$STUB_DIR/unexpected.log"
    exit 1
    ;;
esac
EOF

# fzf スタブ: stdin を fzf.stdin に、引数を fzf.args に残す。
# STUB_FZF_PICK が数字ならその行を返し、"cancel" なら何も返さず 130 で終わる。
cat >"$BIN/fzf" <<'EOF'
#!/bin/bash
cat >"$STUB_DIR/fzf.stdin"
printf '%s\n' "$@" >"$STUB_DIR/fzf.args"
if [ "${STUB_FZF_PICK:-1}" = "cancel" ]; then
  exit 130
fi
sed -n "${STUB_FZF_PICK:-1}p" "$STUB_DIR/fzf.stdin"
EOF

chmod +x "$BIN/herdr" "$BIN/fzf"

STUB_DIR="$WORK/stub"
STUB_TAB_JSON="$WORK/tab.json"
STUB_WS_JSON="$WORK/ws.json"
export STUB_DIR STUB_TAB_JSON STUB_WS_JSON

reset_stub() {
  rm -rf "$STUB_DIR"
  mkdir -p "$STUB_DIR"
}

run_target() {
  env PATH="$BIN:$PATH" STUB_DIR="$STUB_DIR" STUB_TAB_JSON="$STUB_TAB_JSON" \
    STUB_WS_JSON="$STUB_WS_JSON" STUB_FZF_PICK="${STUB_FZF_PICK:-1}" \
    bash "$TARGET"
}

# --- フィクスチャ -----------------------------------------------------------
# 実機の `herdr tab list` の形。label が "1" で重複しており、workspace 名が
# 無いと区別できない（この重複が workspace 列を出す理由そのもの）。
write_default_fixtures() {
  cat >"$STUB_TAB_JSON" <<'EOF'
{"id":"cli:tab:list","result":{"type":"tab_list","tabs":[
{"tab_id":"w1:t4","workspace_id":"w1","label":"1","number":4,"pane_count":3,"agent_status":"unknown","focused":false},
{"tab_id":"w1:t5","workspace_id":"w1","label":"dotfile","number":5,"pane_count":1,"agent_status":"idle","focused":false},
{"tab_id":"w2:t1","workspace_id":"w2","label":"1","number":1,"pane_count":1,"agent_status":"blocked","focused":false},
{"tab_id":"w3:t1","workspace_id":"w3","label":"1","number":1,"pane_count":2,"agent_status":"working","focused":true}
]}}
EOF
  cat >"$STUB_WS_JSON" <<'EOF'
{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[
{"workspace_id":"w1","number":1,"label":"main","tab_count":2,"pane_count":4},
{"workspace_id":"w2","number":2,"label":"review","tab_count":1,"pane_count":1},
{"workspace_id":"w3","number":3,"label":"dotfiles","tab_count":1,"pane_count":2}
]}}
EOF
}

echo "=== 一覧の表示内容 ==="
reset_stub
write_default_fixtures
STUB_FZF_PICK=1 run_target >/dev/null 2>&1
shown="$(strip_ansi <"$STUB_DIR/fzf.stdin")"

check_eq "tab の件数だけ行を出す" "4" "$(printf '%s\n' "$shown" | grep -c .)"
check_contains "workspace 名を出す" "main" "$shown"
check_contains "workspace 名を出す(2)" "review" "$shown"
check_contains "tab 名を出す" "dotfile" "$shown"
check_contains "pane 数を出す" "3 panes" "$shown"
check_contains "pane 数は単数でも panes と書く" "1 panes" "$shown"

focused_line="$(printf '%s\n' "$shown" | grep 'dotfiles')"
check_contains "focus 中の tab に印を付ける" "*" "$focused_line"
unfocused_line="$(printf '%s\n' "$shown" | grep 'review')"
check_not_contains "focus していない tab には印を付けない" "*" "$unfocused_line"

check_contains "working の状態アイコンを出す" "⠋" "$shown"
check_contains "blocked の状態アイコンを出す" "◉" "$shown"
check_contains "idle の状態アイコンを出す" "✓" "$shown"
check_contains "unknown の状態アイコンを出す" "○" "$shown"

echo "=== tab_id は隠しフィールドに置く ==="
check_contains "1列目に tab_id を持つ" "w1:t4	" "$shown"
args="$(cat "$STUB_DIR/fzf.args")"
check_contains "fzf にタブ区切りを伝える" "--delimiter" "$args"
check_contains "fzf の表示は2列目以降に絞る" "2.." "$args"
check_contains "色付きの行を解釈させる" "--ansi" "$args"

echo "=== 選択 → focus ==="
reset_stub
write_default_fixtures
STUB_FZF_PICK=2 run_target >/dev/null 2>&1
rc=$?
check_eq "選択できたら exit 0" "0" "$rc"
check_eq "選んだ行の tab_id を focus に渡す" "w1:t5" "$(cat "$STUB_DIR/focus.log" 2>/dev/null)"

reset_stub
write_default_fixtures
STUB_FZF_PICK=4 run_target >/dev/null 2>&1
check_eq "別の行を選べば別の tab_id を渡す" "w3:t1" "$(cat "$STUB_DIR/focus.log" 2>/dev/null)"

echo "=== キャンセル ==="
reset_stub
write_default_fixtures
STUB_FZF_PICK=cancel run_target >/dev/null 2>&1
rc=$?
check_eq "ESC で抜けても exit 0" "0" "$rc"
if [[ ! -f "$STUB_DIR/focus.log" ]]; then
  ok "ESC のとき focus を呼ばない"
else
  ng "ESC のとき focus を呼ばない" "実際: [$(cat "$STUB_DIR/focus.log")]"
fi

echo "=== tab が0件 ==="
reset_stub
write_default_fixtures
cat >"$STUB_TAB_JSON" <<'EOF'
{"id":"cli:tab:list","result":{"type":"tab_list","tabs":[]}}
EOF
STUB_FZF_PICK=1 run_target >/dev/null 2>&1
rc=$?
check_eq "0件でも exit 0" "0" "$rc"
if [[ ! -f "$STUB_DIR/fzf.stdin" ]]; then
  ok "0件なら fzf を開かない"
else
  ng "0件なら fzf を開かない" "実際: [$(cat "$STUB_DIR/fzf.stdin")]"
fi

echo "=== 欠損フィールドへの耐性 ==="
reset_stub
write_default_fixtures
# workspace list に w9 が無い（新規作成直後などで取り違えた場合）
cat >"$STUB_TAB_JSON" <<'EOF'
{"id":"cli:tab:list","result":{"type":"tab_list","tabs":[
{"tab_id":"w9:t1","workspace_id":"w9","label":"solo","number":1,"pane_count":1,"agent_status":"done","focused":false}
]}}
EOF
STUB_FZF_PICK=1 run_target >/dev/null 2>&1
rc=$?
shown="$(strip_ansi <"$STUB_DIR/fzf.stdin")"
check_eq "workspace 名が引けなくても exit 0" "0" "$rc"
check_contains "workspace 名が引けなければ workspace_id で埋める" "w9" "$shown"
check_contains "tab 名は出し続ける" "solo" "$shown"
check_eq "その行の tab_id を focus に渡せる" "w9:t1" "$(cat "$STUB_DIR/focus.log" 2>/dev/null)"

reset_stub
write_default_fixtures
# 未知の agent_status（herdr 側で状態が増えた場合）
cat >"$STUB_TAB_JSON" <<'EOF'
{"id":"cli:tab:list","result":{"type":"tab_list","tabs":[
{"tab_id":"w1:t1","workspace_id":"w1","label":"x","number":1,"pane_count":1,"agent_status":"brand_new","focused":false}
]}}
EOF
STUB_FZF_PICK=1 run_target >/dev/null 2>&1
rc=$?
check_eq "未知の agent_status でも exit 0" "0" "$rc"
check_contains "未知の状態は行を落とさず出す" "x" "$(strip_ansi <"$STUB_DIR/fzf.stdin")"

echo "=== herdr の呼び方 ==="
if [[ ! -f "$STUB_DIR/unexpected.log" ]]; then
  ok "想定外の herdr サブコマンドを呼ばない"
else
  ng "想定外の herdr サブコマンドを呼ばない" "$(cat "$STUB_DIR/unexpected.log")"
fi

echo ""
echo "================================"
echo "合計: $TOTAL / PASS: $PASS / FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
