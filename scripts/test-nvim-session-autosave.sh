#!/bin/bash
# nvim セッションの自動保存テスト
#
# herdr サーバーを再起動すると、各ペインの nvim は SIGTERM/SIGHUP で終了させられる。
# auto-session の保存契機は VimLeavePre のみで、かつシグナル終了時はセッションファイル
# 破損対策として保存をスキップしている（pre_save_cmds の v:dying チェック）。
# そのため稼働中に定期保存していないと、`he` がペインを復元しても nvim は
# 「最後に :q で終了したときの状態」までしか戻らない。
#
# 検証内容:
#   1. SIGTERM で殺されても直前に開いていたバッファがセッションに保存されている
#   2. 通常終了(:qa)でも従来どおり保存される（既存挙動の非回帰）
#   3. ファイル引数付き起動では保存されない（args_allow_files_auto_save=false の維持）
set -uo pipefail

SESSION_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/sessions"

PASS=0
FAIL=0

TMP_DIRS=()
SESSION_FILES=()

cleanup() {
  for d in "${TMP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
  for f in "${SESSION_FILES[@]:-}"; do
    [[ -n "$f" && -f "$f" ]] && rm -f "$f"
  done
}
trap cleanup EXIT

ok() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}

ng() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}

# 一時作業ディレクトリを作り、テスト用ファイルを置く。
# mktemp のランダム部分をセッションファイル特定のキーに使う。
make_workdir() {
  local d
  d=$(mktemp -d)
  TMP_DIRS+=("$d")
  echo "alpha" >"$d/alpha.txt"
  echo "bravo" >"$d/bravo.txt"
  echo "$d"
}

# workdir に対応する auto-session のセッションファイルパスを返す（無ければ空文字）。
# auto-session は cwd を URL エンコードしたファイル名を使うため、
# mktemp のランダム部分での前方一致で特定する。
find_session_file() {
  local workdir="$1"
  local key="${workdir##*/}"
  key="${key#tmp.}"
  local f
  f=$(find "$SESSION_DIR" -maxdepth 1 -name "*${key}*" -print -quit 2>/dev/null)
  echo "$f"
}

# nvim をヘッドレス起動し、ソケットが応答するまで待つ。PID は NVIM_PID に入れる。
# 引数付き起動を試すため、追加引数をそのまま渡せるようにしている。
# コマンド置換で PID を返すと、バックグラウンドのサブシェルが置換用パイプを
# 掴んだままになりハングするため、グローバル変数で受け渡す。
NVIM_PID=""
start_nvim() {
  local workdir="$1"
  local sock="$2"
  shift 2
  # auto-session は headless では auto_save/auto_restore を無効化する。
  # AUTOSESSION_UNIT_TESTING はそのためのプラグイン公式のテスト用エスケープハッチで、
  # headless 判定だけを外す。args_allow_files_auto_save などの判定は残るため、
  # ケース3の非回帰検証は有効なまま。
  (cd "$workdir" && exec env AUTOSESSION_UNIT_TESTING=1 nvim --headless --listen "$sock" "$@") >/dev/null 2>&1 &
  NVIM_PID=$!
  for _ in $(seq 1 60); do
    if nvim --server "$sock" --remote-expr '1' >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

edit_file() {
  local sock="$1"
  local path="$2"
  nvim --server "$sock" --remote-expr "execute('edit $path')" >/dev/null 2>&1
}

# --- ケース1: SIGTERM で殺されても直前の状態が保存されている ---
test_saved_on_sigterm() {
  echo "ケース1: SIGTERM 終了時にセッションが保存される"
  local workdir sock pid session
  workdir=$(make_workdir)
  sock="$workdir/nvim.sock"

  if ! start_nvim "$workdir" "$sock"; then
    ng "nvim が起動しなかった"
    return
  fi
  pid=$NVIM_PID

  edit_file "$sock" "$workdir/alpha.txt"
  edit_file "$sock" "$workdir/bravo.txt"

  # 定期保存のデバウンスが切れるのを待つ
  sleep 10

  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sleep 1

  session=$(find_session_file "$workdir")
  if [[ -z "$session" ]]; then
    ng "セッションファイルが保存されていない"
    return
  fi
  SESSION_FILES+=("$session")

  if grep -q "alpha.txt" "$session" && grep -q "bravo.txt" "$session"; then
    ok "開いていたバッファがセッションに含まれる"
  else
    ng "セッションに alpha.txt / bravo.txt が含まれない"
  fi
}

# --- ケース2: 通常終了でも保存される（非回帰） ---
test_saved_on_clean_quit() {
  echo "ケース2: 通常終了(:qa)でセッションが保存される"
  local workdir sock pid session
  workdir=$(make_workdir)
  sock="$workdir/nvim.sock"

  if ! start_nvim "$workdir" "$sock"; then
    ng "nvim が起動しなかった"
    return
  fi
  pid=$NVIM_PID

  edit_file "$sock" "$workdir/alpha.txt"
  # デバウンス前に終了させ、VimLeavePre 経由の保存だけを見る
  nvim --server "$sock" --remote-send ':qa<CR>' >/dev/null 2>&1
  wait "$pid" 2>/dev/null
  sleep 1

  session=$(find_session_file "$workdir")
  if [[ -z "$session" ]]; then
    ng "セッションファイルが保存されていない"
    return
  fi
  SESSION_FILES+=("$session")

  if grep -q "alpha.txt" "$session"; then
    ok "通常終了でも従来どおり保存される"
  else
    ng "セッションに alpha.txt が含まれない"
  fi
}

# --- ケース3: ファイル引数付き起動では保存しない（非回帰） ---
# `nvim somefile` でプロジェクトセッションを上書きしないための既存仕様
# (args_allow_files_auto_save = false) を、定期保存が破らないことを確認する。
test_not_saved_with_file_args() {
  echo "ケース3: ファイル引数付き起動ではセッションを保存しない"
  local workdir sock pid session
  workdir=$(make_workdir)
  sock="$workdir/nvim.sock"

  if ! start_nvim "$workdir" "$sock" "alpha.txt"; then
    ng "nvim が起動しなかった"
    return
  fi
  pid=$NVIM_PID

  sleep 10

  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sleep 1

  session=$(find_session_file "$workdir")
  if [[ -n "$session" ]]; then
    SESSION_FILES+=("$session")
    ng "ファイル引数付き起動なのにセッションが保存された"
  else
    ok "ファイル引数付き起動ではセッションを保存しない"
  fi
}

echo "=== nvim セッション自動保存テスト ==="
test_saved_on_sigterm
test_saved_on_clean_quit
test_not_saved_with_file_args

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
