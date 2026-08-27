#!/bin/bash
# fish関数 winpath のユニットテスト
#
# winpath は WSLのパスを Windows側の表記（`\\wsl.localhost\<distro>\...` または `C:\...`）へ
# 変換して出力し、`-c` でclipboardへも入れる。変換そのものは `wslpath -w` に委譲するので、
# この関数の責務は「引数の解釈」「存在しないパスの警告」「clipboard backendの選択」に絞られる。
#
# **依存コマンドは全てPATHのスタブへ差し替える。** 実 `wslpath` を使うとWSL上でしか
# 走らなくなり（CIで落ちる）、実 `win32yank.exe` を使うとテストが端末のclipboardを
# 破壊する。
#
# PATHには /usr/bin を入れない。/usr/bin/wslpath が実在するため、入れると「非WSL環境」
# （wslpath が無い状態）を再現できない。代わりにスタブが必要とする cat だけを $SYSBIN へ
# symlinkして渡す。winpath 本体が使う printf・test・type・string は全て fish のbuiltinで、
# 外部コマンドを必要としない。
#
# clipboardの内容は `cat "$file"` で比較しない。コマンド置換が末尾改行を落とすため、
# 「末尾改行を付けない」という一番壊れやすい約束が検証できなくなる。`cmp` でバイト比較する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WINPATH="$REPO_ROOT/.config/fish/my/functions/winpath.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi
FISH_BIN="$(command -v fish)"
if [[ ! -f "$WINPATH" ]]; then
  echo "ERROR: $WINPATH が存在しません"
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
TOTAL=0

ok() {
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

ng() {
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
  echo "    expected: [$2]"
  echo "    actual:   [$3]"
}

# ---- スタブ ----------------------------------------------------------------
# wslpath: `-w <path>` だけを受け、決定的な `WIN(<path>)` を返す。パスに FAILME を
# 含む場合だけ失敗させ、変換失敗の経路を踏ませる。
STUB_FULL="$TMP/stub-full"     # wslpath + win32yank.exe + clip.exe
STUB_CLIP="$TMP/stub-clip"     # wslpath + clip.exe のみ（win32yankフォールバック検証）
STUB_NOCLIP="$TMP/stub-noclip" # wslpath のみ
STUB_NOWSL="$TMP/stub-nowsl"   # 空（wslpath すら無い＝非WSL環境）
mkdir -p "$STUB_FULL" "$STUB_CLIP" "$STUB_NOCLIP" "$STUB_NOWSL"

# スタブ（#!/bin/bash）が使う外部コマンドだけを通す最小のsystem bin
SYSBIN="$TMP/sysbin"
mkdir -p "$SYSBIN"
ln -s "$(command -v cat)" "$SYSBIN/cat"

make_wslpath() {
  cat >"$1/wslpath" <<'STUB'
#!/bin/bash
if [[ "$1" != "-w" ]]; then
  echo "stub wslpath: unexpected args: $*" >&2
  exit 2
fi
if [[ "$2" == *FAILME* ]]; then
  echo "stub wslpath: cannot convert: $2" >&2
  exit 1
fi
echo "WIN($2)"
STUB
  chmod +x "$1/wslpath"
}

# clipboardスタブ: stdinを $WINPATH_STUB_OUT へ、引数を .args へ、自分の名前を .name へ落とす。
make_clipper() {
  local dir="$1" name="$2"
  cat >"$dir/$name" <<STUB
#!/bin/bash
printf '%s' "$name" > "\$WINPATH_STUB_OUT.name"
printf '%s' "\$*" > "\$WINPATH_STUB_OUT.args"
cat > "\$WINPATH_STUB_OUT"
STUB
  chmod +x "$dir/$name"
}

make_wslpath "$STUB_FULL"
make_wslpath "$STUB_CLIP"
make_wslpath "$STUB_NOCLIP"
make_clipper "$STUB_FULL" "win32yank.exe"
make_clipper "$STUB_FULL" "clip.exe"
make_clipper "$STUB_CLIP" "clip.exe"

# ---- 実行対象のワークディレクトリ ------------------------------------------
WORK="$TMP/work"
mkdir -p "$WORK/sub"
: >"$WORK/a.txt"

CLIP_OUT="$TMP/clipboard"
OUT="$TMP/stdout"
ERR="$TMP/stderr"
STATUS=0

# run <stubdir> [args...]
#
# `-c` を winpath へ届けるため、fish の `-c` script の後ろに `--` を挟む。挟まないと
# テスト側の `-c` を fish 自身のオプションとして食われ、次の引数がコマンドとして実行される。
run() {
  local stubdir="$1"
  shift
  rm -f "$CLIP_OUT" "$CLIP_OUT.args" "$CLIP_OUT.name"
  (
    cd "$WORK" && timeout 10 env \
      PATH="$stubdir:$SYSBIN" \
      WINPATH_STUB_OUT="$CLIP_OUT" \
      "$FISH_BIN" --no-config -c "source $WINPATH; winpath \$argv" -- "$@"
  ) >"$OUT" 2>"$ERR"
  STATUS=$?
}

assert_stdout() {
  local name="$1" expected="$2" actual
  actual="$(cat "$OUT")"
  if [[ "$actual" == "$expected" ]]; then
    ok "$name"
  else
    ng "$name" "$expected" "$actual"
  fi
}

assert_status() {
  local name="$1" expected="$2"
  if [[ "$STATUS" == "$expected" ]]; then
    ok "$name"
  else
    ng "$name" "status=$expected" "status=$STATUS"
  fi
}

assert_stderr_has() {
  local name="$1" needle="$2"
  if grep -qF -- "$needle" "$ERR"; then
    ok "$name"
  else
    ng "$name" "stderr contains [$needle]" "$(cat "$ERR")"
  fi
}

assert_stderr_empty() {
  local name="$1"
  if [[ ! -s "$ERR" ]]; then
    ok "$name"
  else
    ng "$name" "stderr empty" "$(cat "$ERR")"
  fi
}

# clipboardの内容をバイト単位で比較する（末尾改行の有無まで見る）
assert_clipboard() {
  local name="$1" expected="$2"
  if [[ ! -f "$CLIP_OUT" ]]; then
    ng "$name" "$expected" "(clipboardへ書かれていない)"
    return
  fi
  if printf '%s' "$expected" | cmp -s - "$CLIP_OUT"; then
    ok "$name"
  else
    ng "$name" "$(printf '%s' "$expected" | od -c | head -3)" "$(od -c <"$CLIP_OUT" | head -3)"
  fi
}

assert_file_content() {
  local name="$1" file="$2" expected="$3" actual
  actual="$(cat "$file" 2>/dev/null)"
  if [[ "$actual" == "$expected" ]]; then
    ok "$name"
  else
    ng "$name" "$expected" "$actual"
  fi
}

assert_clipboard_untouched() {
  local name="$1"
  if [[ ! -f "$CLIP_OUT" ]]; then
    ok "$name"
  else
    ng "$name" "(clipboardへ書かない)" "$(cat "$CLIP_OUT")"
  fi
}

echo "=== winpath: 変換と出力 ==="

# 引数なしはカレントディレクトリを対象にする。`.` をそのまま wslpath へ渡し、
# 絶対パス化も wslpath に任せる（実 wslpath は `.` を絶対パスへ解決する）。
run "$STUB_FULL"
assert_stdout "引数なしはカレントディレクトリを変換する" 'WIN(.)'
assert_status "引数なしは成功する" 0
assert_stderr_empty "引数なしは警告を出さない"
assert_clipboard_untouched "-c 無しではclipboardへ書かない"

run "$STUB_FULL" a.txt
assert_stdout "相対パスをそのまま wslpath へ渡す" 'WIN(a.txt)'

run "$STUB_FULL" /data/git-repos
assert_stdout "絶対パスを変換する" 'WIN(/data/git-repos)'

run "$STUB_FULL" a.txt sub
assert_stdout "複数引数は与えた順に1行ずつ出す" 'WIN(a.txt)
WIN(sub)'
assert_status "複数引数は成功する" 0

echo
echo "=== winpath: 存在しないパスと変換失敗 ==="

# 存在しないパスは警告だけ出して変換結果は返す。まだ作っていないファイルの置き場を
# Explorerへ貼りたいケースがあるため、ここで打ち切らない。
run "$STUB_FULL" /nonexistent-winpath-test
assert_stdout "存在しないパスでも変換結果を出す" 'WIN(/nonexistent-winpath-test)'
assert_status "存在しないパスは成功扱いにする" 0
assert_stderr_has "存在しないパスは警告を出す" "存在しないパス"

run "$STUB_FULL" a.txt sub
assert_stderr_empty "存在するパスだけなら警告を出さない"

# 変換失敗は該当引数だけを飛ばし、残りは処理して最後に失敗を返す。
run "$STUB_FULL" a.txt FAILME sub
assert_stdout "変換に失敗した引数を飛ばして残りを出す" 'WIN(a.txt)
WIN(sub)'
assert_status "変換失敗があれば1を返す" 1
assert_stderr_has "変換失敗をstderrへ出す" "変換に失敗"

echo
echo "=== winpath: clipboard ==="

# clipboardへは末尾改行を付けない。Explorerのアドレスバーへ貼ったとき、改行が
# Enterとして食われて意図しない遷移が起きる。
run "$STUB_FULL" -c a.txt
assert_clipboard "-c は末尾改行なしでclipboardへ入れる" 'WIN(a.txt)'
assert_stdout "-c でもstdoutへ結果を出す" 'WIN(a.txt)'
assert_status "-c は成功する" 0
assert_stderr_has "-c はコピーした旨をstderrへ出す" "copied"
assert_file_content "win32yank.exe を優先して使う" "$CLIP_OUT.name" "win32yank.exe"
assert_file_content "win32yank.exe は -i --crlf で呼ぶ" "$CLIP_OUT.args" "-i --crlf"

run "$STUB_FULL" --copy a.txt
assert_clipboard "--copy も -c と同じ" 'WIN(a.txt)'

run "$STUB_FULL" a.txt -c
assert_clipboard "-c は引数の後ろに置いても効く" 'WIN(a.txt)'

run "$STUB_FULL" -c a.txt sub
assert_clipboard "複数引数は改行区切りで末尾改行なし" 'WIN(a.txt)
WIN(sub)'

# win32yank は bootstrap の管理外で、新環境では未導入のことがある。WSLなら必ずある
# clip.exe へ落とす。
run "$STUB_CLIP" -c a.txt
assert_clipboard "win32yank.exe が無ければ clip.exe を使う" 'WIN(a.txt)'
assert_file_content "フォールバック先は clip.exe" "$CLIP_OUT.name" "clip.exe"
assert_status "clip.exe へのフォールバックは成功する" 0

run "$STUB_NOCLIP" -c a.txt
assert_stdout "clipboardコマンドが無くてもstdoutへは出す" 'WIN(a.txt)'
assert_status "clipboardコマンドが無ければ1を返す" 1
assert_stderr_has "clipboardコマンドが無い旨をstderrへ出す" "clipboard"

echo
echo "=== winpath: 非WSL環境 ==="

# 判定は wslpath の有無だけで足りる。wslpath はWSL内にしか存在しない。
run "$STUB_NOWSL" a.txt
assert_stdout "非WSLでは何も出力しない" ''
assert_status "非WSLでは1を返す" 1
assert_stderr_has "非WSLである旨をstderrへ出す" "WSL"

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]]
