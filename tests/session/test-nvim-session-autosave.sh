#!/bin/bash
# serial: 保存されないことの検査はデバウンス後の負の待ちが必要で、負荷の影響を受ける
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
#   4. 全プロジェクト共有のスクラッチパッドを表示中は保存しない
#   5. スクラッチパッドを閉じれば保存が再開する（4がやりすぎでないこと）
#   6. :checkhealth の結果を定期保存が閉じない（今回の障害の回帰テスト）
#
# ci-skip: 実 nvim 設定と auto-session プラグインの導入済み環境が要る
set -uo pipefail

TEST_ROOT=$(mktemp -d)
SESSION_DIR="$TEST_ROOT/sessions"
mkdir -p "$SESSION_DIR" "$TEST_ROOT/cache" "$TEST_ROOT/state" "$TEST_ROOT/runtime"
chmod 700 "$TEST_ROOT/runtime"
export MY_AUTOSESSION_ROOT_DIR="$SESSION_DIR"
# 実設定を読み込んでもLua cache・ShaDa・logを実HOMEへ書かない。
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"

# 定期保存のデバウンス。テスト中だけ短縮する（auto-session.lua が
# MY_AUTOSESSION_SAVE_DEBOUNCE_MS で上書きを受け付ける）。
# 本番の 5000ms のまま固定 sleep で待つと、このテスト1本でスイート全体が
# 50秒伸び、run-tests.sh が止まって見える。
SAVE_DEBOUNCE_MS="${SAVE_DEBOUNCE_MS:-300}"

# 本番の既定値。短縮の副作用で本番値が下がっていないことを固定する。
AUTOSESSION_CONFIG="$(cd "$(dirname "$0")/../.." && pwd)/.config/nvim/lua/my/plugins/tools/auto-session.lua"
EXPECTED_DEFAULT_DEBOUNCE_MS=5000

# 除外対象は auto-session.lua 側にパスで直書きしているため、テストも実物を使う。
# :edit するだけで書き込まないので中身は変わらない。
SCRATCHPAD="$HOME/.inbox.md"

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
  rm -rf "$TEST_ROOT"
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
  (cd "$workdir" && exec env AUTOSESSION_UNIT_TESTING=1 \
    MY_AUTOSESSION_SAVE_DEBOUNCE_MS="$SAVE_DEBOUNCE_MS" \
    nvim --headless --listen "$sock" "$@") >/dev/null 2>&1 &
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

# セッションが書かれるのを待つ（正の待ち）。固定 sleep ではなく条件で待つ。
# デバウンスが切れて保存が走ればすぐ返るので、待ち時間が実測に張り付く。
wait_for_session_file() {
  local workdir="$1"
  local deadline=$((SECONDS + 15))
  while ((SECONDS < deadline)); do
    if [[ -n "$(find_session_file "$workdir")" ]]; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# 「保存されないこと」を確かめるための待ち（負の待ち）。待つ対象が無いので
# 条件 poll にできず、デバウンスを確実に越える固定待ちが要る。
# デバウンスの5倍を待つ（短縮しているので実時間は短い）。
settle_debounce() {
  sleep "$(awk -v ms="$SAVE_DEBOUNCE_MS" 'BEGIN { printf "%.2f", ms * 5 / 1000 }')"
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

  # 定期保存が走るまで待つ
  wait_for_session_file "$workdir"

  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

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

  # 保存されないことを見るので、デバウンスを越えて待つ
  settle_debounce

  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  session=$(find_session_file "$workdir")
  if [[ -n "$session" ]]; then
    SESSION_FILES+=("$session")
    ng "ファイル引数付き起動なのにセッションが保存された"
  else
    ok "ファイル引数付き起動ではセッションを保存しない"
  fi
}

# --- ケース4: スクラッチパッド表示中は保存しない ---
# ~/.inbox.md は全プロジェクトで共有するスクラッチパッド。プロジェクト固有の
# セッションに載ると、復元時にどのペインでも同じスクラッチパッドが画面に出る。
# 直前に保存された alpha.txt の状態が維持されることを確認する。
test_not_saved_while_scratchpad_visible() {
  echo "ケース4: スクラッチパッド表示中はセッションを保存しない"
  local workdir sock pid session
  workdir=$(make_workdir)
  sock="$workdir/nvim.sock"

  if ! start_nvim "$workdir" "$sock"; then
    ng "nvim が起動しなかった"
    return
  fi
  pid=$NVIM_PID

  edit_file "$sock" "$workdir/alpha.txt"
  # ここで alpha.txt の状態が一度保存される
  wait_for_session_file "$workdir"

  edit_file "$sock" "$SCRATCHPAD"
  # スクラッチパッドで上書きされないことを見るので、デバウンスを越えて待つ
  settle_debounce

  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  session=$(find_session_file "$workdir")
  if [[ -z "$session" ]]; then
    ng "セッションファイルが保存されていない"
    return
  fi
  SESSION_FILES+=("$session")

  if grep -q '^edit .*\.inbox\.md' "$session"; then
    ng "スクラッチパッドがセッションの表示バッファとして保存された"
  else
    ok "スクラッチパッドはセッションの表示バッファにならない"
  fi

  if grep -q '^edit .*alpha\.txt' "$session"; then
    ok "直前に保存された状態が維持される"
  else
    ng "セッションの表示バッファが alpha.txt でない"
  fi
}

# --- ケース5: スクラッチパッドを閉じれば保存が再開する ---
# ケース4の抑止が「スクラッチパッドを一度開いたら以後保存しない」に
# なっていないことを確認する。
test_saved_after_scratchpad_closed() {
  echo "ケース5: スクラッチパッドを閉じればセッション保存が再開する"
  local workdir sock pid session
  workdir=$(make_workdir)
  sock="$workdir/nvim.sock"

  if ! start_nvim "$workdir" "$sock"; then
    ng "nvim が起動しなかった"
    return
  fi
  pid=$NVIM_PID

  edit_file "$sock" "$workdir/alpha.txt"
  edit_file "$sock" "$SCRATCHPAD"
  edit_file "$sock" "$workdir/bravo.txt"
  wait_for_session_file "$workdir"

  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  session=$(find_session_file "$workdir")
  if [[ -z "$session" ]]; then
    ng "セッションファイルが保存されていない"
    return
  fi
  SESSION_FILES+=("$session")

  if grep -q '^edit .*bravo\.txt' "$session"; then
    ok "スクラッチパッドを離れた後の状態が保存される"
  else
    ng "セッションの表示バッファが bravo.txt でない"
  fi
}

# --- ケース6: checkhealth 表示中は保存せず、結果画面を閉じない ---
# auto-session は session 保存前に filetype=checkhealth のバッファを削除する。
# 定期保存からそれを呼ぶと、結果画面がデバウンス後に勝手に閉じていた。
test_checkhealth_stays_open() {
  echo "ケース6: checkhealth の結果画面を定期保存が閉じない"
  local workdir sock pid health_count
  workdir=$(make_workdir)
  sock="$workdir/nvim.sock"

  if ! start_nvim "$workdir" "$sock"; then
    ng "nvim が起動しなかった"
    return
  fi
  pid=$NVIM_PID

  edit_file "$sock" "$workdir/alpha.txt"
  wait_for_session_file "$workdir"
  nvim --server "$sock" --remote-expr "execute('checkhealth')" >/dev/null 2>&1

  # checkhealth の BufEnter で予約された定期保存が発火する時刻を越える。
  settle_debounce
  health_count=$(nvim --server "$sock" --remote-expr \
    "len(filter(getbufinfo(), {_, v -> getbufvar(v.bufnr, '&filetype') ==# 'checkhealth'}))" 2>/dev/null)

  if [[ "$health_count" =~ ^[1-9][0-9]*$ ]]; then
    ok "checkhealth の結果バッファが表示されたまま"
  else
    ng "checkhealth の結果バッファが定期保存で閉じられた"
  fi

  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
}

# --- ケース0: 本番のデバウンス既定値が下がっていない ---
# テストは短縮した値で走るので、本番値の退行をここで止める。
test_production_debounce_default() {
  echo "ケース0: 本番のデバウンス既定値が ${EXPECTED_DEFAULT_DEBOUNCE_MS}ms のまま"
  if [[ ! -f "$AUTOSESSION_CONFIG" ]]; then
    ng "auto-session.lua が見つからない: $AUTOSESSION_CONFIG"
    return
  fi
  if grep -qE "or ${EXPECTED_DEFAULT_DEBOUNCE_MS}\b" "$AUTOSESSION_CONFIG"; then
    ok "既定値が ${EXPECTED_DEFAULT_DEBOUNCE_MS}ms"
  else
    ng "既定値が ${EXPECTED_DEFAULT_DEBOUNCE_MS}ms でない（auto-session.lua を確認）"
  fi
}

echo "=== nvim セッション自動保存テスト ==="
test_production_debounce_default
test_saved_on_sigterm
test_saved_on_clean_quit
test_not_saved_with_file_args
test_not_saved_while_scratchpad_visible
test_saved_after_scratchpad_closed
test_checkhealth_stays_open

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
