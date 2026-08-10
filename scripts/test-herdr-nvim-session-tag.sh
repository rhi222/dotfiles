#!/bin/bash
# auto-session のセッションが herdr のペイン単位に分かれることの検証
#
# XDG_DATA_HOME を差し替えるとプラグイン(lazy)の置き場ごと変わってしまうため、
# 実際のセッションディレクトリを使い、一時 cwd 由来のセッションだけを後始末する。
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

SESSION_DIR="$HOME/.local/share/nvim/sessions"
WORK=$(mktemp -d)

# auto-session はセッション名をエスケープしてファイル名にする。
# 一時ディレクトリのパスに含まれる / と . が %2F / %2E になる。
session_key() {
  printf '%s' "$WORK" | sed -e 's|/|%2F|g' -e 's|\.|%2E|g'
}

cleanup() {
  # 一時 cwd 由来のセッションだけを消す（ディレクトリ名がファイル名にエンコードされている）
  find "$SESSION_DIR" -maxdepth 1 -name "*$(session_key)*" -delete 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected: $expected"
    echo "    actual  : $actual"
  fi
}

# auto-session は headless では保存・復元を止める（init.lua の in_headless_mode）。
# プラグイン自身がテスト用に用意している解除フラグを立てる。
export AUTOSESSION_UNIT_TESTING=1

# 素の nvim を起動し、指定ファイルを開いてから終了する。
# ファイル引数付きの起動は args_allow_files_auto_save = false で保存対象外に
# なるため、必ず :edit で開く。
run_nvim() {
  local pane="$1" file="$2"
  (cd "$WORK" && HERDR_PANE_ID="$pane" nvim --headless -c "edit $file" -c "wqa") >/dev/null 2>&1
}

# 復元されたバッファ名（basename のカンマ区切り）を取り出す。
# VimEnter での自動復元は headless では走らないため、復元を明示的に呼ぶ。
# ここで確かめたいのは「そのペインのセッションに何が入っているか」であって、
# nvim の起動タイミングではない。
# 復元通知など他の出力と混ざらないよう、結果はファイル経由で受け取る。
restored_buffers() {
  local pane="$1"
  local out="$WORK/.buffers.$pane"
  (cd "$WORK" && HERDR_PANE_ID="$pane" nvim --headless \
    -c 'lua require("auto-session").auto_restore_session()' \
    -c "lua vim.fn.writefile({table.concat(vim.tbl_map(function(b) return vim.fn.fnamemodify(b.name, ':t') end, vim.fn.getbufinfo({buflisted=1})), ',')}, '$out')" \
    -c 'qa!') >/dev/null 2>&1
  cat "$out" 2>/dev/null
}

count_sessions() {
  find "$SESSION_DIR" -maxdepth 1 -name "*$(session_key)*" | wc -l | tr -d ' '
}

echo "test: 同じ cwd でもペインごとに別セッションになる"
: >"$WORK/a.txt"
: >"$WORK/b.txt"
run_nvim "w9:p1" a.txt
run_nvim "w9:p2" b.txt
assert_eq "セッションファイルが2つできる" "2" "$(count_sessions)"

echo "test: 復元したバッファがペインごとに異なる"
assert_eq "w9:p1 は a.txt を復元する" "a.txt" "$(restored_buffers w9:p1)"
assert_eq "w9:p2 は b.txt を復元する" "b.txt" "$(restored_buffers w9:p2)"

echo ""
echo "TOTAL=$TOTAL PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
