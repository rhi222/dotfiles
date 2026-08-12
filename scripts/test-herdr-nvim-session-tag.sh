#!/bin/bash
# auto-session のセッションが herdr のペイン単位に分かれることの検証
#
# XDG_DATA_HOME を差し替えるとプラグイン(lazy)の置き場ごと変わってしまうため、
# 実際のセッションディレクトリを使い、一時 cwd 由来のセッションだけを後始末する。
#
# ci-skip: 実 nvim 設定と auto-session プラグインの導入済み環境が要る
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

# herdr の外で nvim を動かし、タグ無し（cwd 単位）のセッションを作る。
run_nvim_untagged() {
  local file="$1"
  (cd "$WORK" && env -u HERDR_PANE_ID nvim --headless -c "edit $file" -c "wqa") >/dev/null 2>&1
}

# タグ付きセッションのファイル名は "<cwd>||<pane_id>" をエスケープしたもの。
# | は %7C、: は %3A になる。
tagged_session_exists() {
  local pane_escaped
  pane_escaped=$(printf '%s' "$1" | sed 's|:|%3A|g')
  [[ -f "$SESSION_DIR/$(session_key)%7C%7C$pane_escaped.vim" ]] && echo present || echo absent
}

# フォールバック復元は no_restore フック経由で走る。
# auto_restore_session() はこのフックを発火しないため、VimEnter 用の
# 入口を直接呼ぶ。qa! で抜けるので、終了時の保存も併せて確認できる。
restored_buffers_at_vim_enter() {
  local pane="$1"
  local out="$WORK/.enter.$pane"
  (cd "$WORK" && HERDR_PANE_ID="$pane" nvim --headless \
    -c 'lua require("auto-session").auto_restore_session_at_vim_enter()' \
    -c "lua vim.fn.writefile({table.concat(vim.tbl_map(function(b) return vim.fn.fnamemodify(b.name, ':t') end, vim.fn.getbufinfo({buflisted=1})), ',')}, '$out')" \
    -c 'qa!') >/dev/null 2>&1
  cat "$out" 2>/dev/null
}

# ファイル引数付きの起動を再現する。
# auto-session はこの場合「復元しない」と判断するが、その判断も no_restore
# フックを発火させる。ここでフォールバックが走ると、開こうとしたファイルが
# セッションの内容で上書きされてしまう。
restored_buffers_with_file_arg() {
  local pane="$1" file="$2"
  local out="$WORK/.arg.$pane"
  (cd "$WORK" && HERDR_PANE_ID="$pane" nvim --headless "$file" \
    -c 'lua require("auto-session").auto_restore_session_at_vim_enter()' \
    -c "lua vim.fn.writefile({table.concat(vim.tbl_map(function(b) return vim.fn.fnamemodify(b.name, ':t') end, vim.fn.getbufinfo({buflisted=1})), ',')}, '$out')" \
    -c 'qa!') >/dev/null 2>&1
  cat "$out" 2>/dev/null
}

# 実運用の headless 起動（daily-update の `nvim --headless "+Lazy! sync"` など）を
# 再現する。auto-session はここでも復元しないと判断するが no_restore は発火する。
# 冒頭で立てているテスト用の解除フラグを外し、素の headless 判定を働かせる。
restored_buffers_headless() {
  local pane="$1"
  local out="$WORK/.headless.$pane"
  (cd "$WORK" && env -u AUTOSESSION_UNIT_TESTING HERDR_PANE_ID="$pane" nvim --headless \
    -c 'lua require("auto-session").auto_restore_session_at_vim_enter()' \
    -c "lua vim.fn.writefile({table.concat(vim.tbl_map(function(b) return vim.fn.fnamemodify(b.name, ':t') end, vim.fn.getbufinfo({buflisted=1})), ',')}, '$out')" \
    -c 'qa!') >/dev/null 2>&1
  cat "$out" 2>/dev/null
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

echo "test: タグ付きが無ければ cwd 単位のセッションへフォールバックする"
: >"$WORK/c.txt"
run_nvim_untagged c.txt
assert_eq "w9:p3 のタグ付きセッションはまだ無い" "absent" "$(tagged_session_exists w9:p3)"
assert_eq "未知のペインはタグ無しセッションを復元する" "c.txt" "$(restored_buffers_at_vim_enter w9:p3)"
assert_eq "フォールバック後の保存はタグ付きになる" "present" "$(tagged_session_exists w9:p3)"

echo "test: タグ付きがあればフォールバックしない"
assert_eq "w9:p1 は自分のセッションを復元する" "a.txt" "$(restored_buffers_at_vim_enter w9:p1)"

echo "test: ファイル引数付きの起動ではフォールバックしない"
: >"$WORK/d.txt"
run_nvim_untagged c.txt
assert_eq "w9:p4 のタグ付きセッションはまだ無い" "absent" "$(tagged_session_exists w9:p4)"
assert_eq "指定したファイルだけが開かれる" "d.txt" "$(restored_buffers_with_file_arg w9:p4 d.txt)"

echo "test: headless 起動ではフォールバックしない"
run_nvim_untagged c.txt
assert_eq "w9:p5 のタグ付きセッションはまだ無い" "absent" "$(tagged_session_exists w9:p5)"
assert_eq "バッファは復元されない" "" "$(restored_buffers_headless w9:p5)"

echo ""
echo "TOTAL=$TOTAL PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
