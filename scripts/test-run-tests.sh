#!/bin/bash
# serial: 並列化と打ち切りの検証で自分が経過時間を測るので、隣に負荷があると落ちる
# run-tests.sh のテスト。偽のテスト群を作った一時ディレクトリを対象にする
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/run-tests.sh"

pass=0
fail=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "NG: $desc"
    fail=$((fail + 1))
  fi
}

if [[ ! -f "$RUNNER" ]]; then
  echo "ERROR: $RUNNER が存在しません"
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make_test() {
  local name="$1" body="$2"
  printf '#!/bin/bash\n%s\n' "$body" >"$tmp/$name"
  chmod +x "$tmp/$name"
}

# --- 全部成功 ---
make_test test-alpha.sh 'exit 0'
make_test test-beta.sh 'exit 0'

out=$(TEST_DIR="$tmp" bash "$RUNNER" 2>&1)
rc=$?
check "全部成功なら exit 0" test "$rc" -eq 0
check "実行した件数を出す" grep -qE '2 *件|2/2|pass: 2' <<<"$out"
check "個々のテスト名を出す" grep -q "test-alpha.sh" <<<"$out"

# --- 1本失敗 ---
make_test test-gamma.sh 'echo "ここで落ちた理由"; exit 1'

out=$(TEST_DIR="$tmp" bash "$RUNNER" 2>&1)
rc=$?
check "1本でも失敗したら非0で終わる" test "$rc" -ne 0
check "失敗したテスト名がサマリに出る" grep -q "test-gamma.sh" <<<"$out"
check "失敗したテストの出力を表示する" grep -q "ここで落ちた理由" <<<"$out"
check "失敗しても後続のテストを続行する" grep -q "test-beta.sh" <<<"$out"
rm -f "$tmp/test-gamma.sh"

# --- ci-skip マーカー ---
make_test test-delta.sh '# ci-skip: 実nvim設定が要る
echo "走ってしまった" >"'"$tmp"'/delta-ran"
exit 0'

rm -f "$tmp/delta-ran"
out=$(TEST_DIR="$tmp" bash "$RUNNER" --ci 2>&1)
rc=$?
check "--ci では ci-skip 付きを実行しない" test ! -f "$tmp/delta-ran"
check "--ci でも他のテストは走る" grep -q "test-alpha.sh" <<<"$out"
check "スキップ理由を表示する" grep -q "実nvim設定が要る" <<<"$out"
check "スキップだけなら exit 0" test "$rc" -eq 0

rm -f "$tmp/delta-ran"
out=$(TEST_DIR="$tmp" bash "$RUNNER" 2>&1)
check "--ci なしなら ci-skip 付きも実行する" test -f "$tmp/delta-ran"
rm -f "$tmp/test-delta.sh" "$tmp/delta-ran"

# --- タイムアウト ---
# ハングしたテストで CI が既定6時間まで回らないこと
make_test test-hang.sh 'sleep 30'
start=$(date +%s)
out=$(TEST_DIR="$tmp" TEST_TIMEOUT=2 bash "$RUNNER" 2>&1)
rc=$?
elapsed=$(($(date +%s) - start))
check "タイムアウトで打ち切る" test "$elapsed" -lt 20
check "タイムアウトは失敗として扱う" test "$rc" -ne 0
check "タイムアウトしたテスト名を出す" grep -q "test-hang.sh" <<<"$out"
rm -f "$tmp/test-hang.sh"

# --- 並列実行 ---
# 直列だと 79本で47秒かかっていた。個々は独立（各テストが mktemp で自分の作業場を
# 作る）なので並列化できる。ただし出力が混ざると読めないので、順序と体裁は
# 直列時と同じでなければならない。
make_test test-slow1.sh 'sleep 1; exit 0'
make_test test-slow2.sh 'sleep 1; exit 0'
make_test test-slow3.sh 'sleep 1; exit 0'
make_test test-slow4.sh 'sleep 1; exit 0'

start=$(date +%s)
out=$(TEST_DIR="$tmp" TEST_JOBS=4 bash "$RUNNER" 2>&1)
rc=$?
elapsed=$(($(date +%s) - start))
check "並列なら 1秒テスト4本が直列より速い" test "$elapsed" -lt 4
check "並列でも exit 0" test "$rc" -eq 0
check "並列でも全件数える" grep -qE 'pass: 6' <<<"$out"

# 出力はテスト名の昇順で、1本1行。並列で混ざらないこと
names=$(grep -oE 'test-[a-z0-9]+\.sh' <<<"$out" | head -6)
sorted=$(printf '%s\n' "$names" | sort)
check "出力はテスト名の昇順（並列でも混ざらない）" test "$names" = "$sorted"

# 失敗時の出力も、そのテストの分だけまとまって出ること
make_test test-slow5.sh 'echo "並列でも読める理由"; exit 1'
out=$(TEST_DIR="$tmp" TEST_JOBS=4 bash "$RUNNER" 2>&1)
rc=$?
check "並列でも失敗を検出する" test "$rc" -ne 0
check "並列でも失敗したテストの出力を見せる" grep -q "並列でも読める理由" <<<"$out"
check "並列でも失敗名をサマリに出す" grep -q "test-slow5.sh" <<<"$out"
rm -f "$tmp"/test-slow*.sh

# TEST_JOBS=1 は直列と同じ挙動
make_test test-serial.sh 'exit 0'
out=$(TEST_DIR="$tmp" TEST_JOBS=1 bash "$RUNNER" 2>&1)
check "TEST_JOBS=1 でも動く" test "$?" -eq 0
check "TEST_JOBS=1 でも件数を出す" grep -qE 'pass: 3' <<<"$out"
rm -f "$tmp/test-serial.sh"

# 並列でもタイムアウトは効く
make_test test-hang2.sh 'sleep 30'
start=$(date +%s)
out=$(TEST_DIR="$tmp" TEST_JOBS=4 TEST_TIMEOUT=2 bash "$RUNNER" 2>&1)
rc=$?
elapsed=$(($(date +%s) - start))
check "並列でもタイムアウトで打ち切る" test "$elapsed" -lt 20
check "並列でもタイムアウトは失敗" test "$rc" -ne 0
rm -f "$tmp/test-hang2.sh"

# 並列でも ci-skip は効く
make_test test-skipme.sh '# ci-skip: 理由
echo ran >"'"$tmp"'/skipme-ran"
exit 0'
rm -f "$tmp/skipme-ran"
out=$(TEST_DIR="$tmp" TEST_JOBS=4 bash "$RUNNER" --ci 2>&1)
check "並列でも ci-skip を実行しない" test ! -f "$tmp/skipme-ran"
check "並列でも skip 件数を出す" grep -qE 'skip: 1' <<<"$out"
rm -f "$tmp/test-skipme.sh" "$tmp/skipme-ran"

# --- serial 宣言 ---
# 並列にすると落ちるテストがある。実 nvim を起動して 5000ms のデバウンスを待つもの、
# 実 $HOME の設定で対話シェルを起動するものなど、負荷で結果が変わる種類。
# ci-skip と同じ形で、テストファイル側が `# serial: <理由>` と宣言する。
make_test test-par1.sh 'exit 0'
make_test test-par2.sh 'exit 0'
make_test test-ser1.sh '# serial: 実nvimの起動時間に依存する
echo "$$" >>"'"$tmp"'/ser.log"
sleep 1
exit 0'
make_test test-ser2.sh '# serial: 実シェルの起動時間に依存する
echo "$$" >>"'"$tmp"'/ser.log"
sleep 1
exit 0'

: >"$tmp/ser.log"
start=$(date +%s)
out=$(TEST_DIR="$tmp" TEST_JOBS=4 bash "$RUNNER" 2>&1)
rc=$?
elapsed=$(($(date +%s) - start))
check "serial 宣言があっても exit 0" test "$rc" -eq 0
check "serial なテストも実行する" grep -q "test-ser1.sh" <<<"$out"
# 2本が直列なので合計2秒以上かかる（並列なら1秒で終わってしまう）
check "serial なテストは同時に走らない" test "$elapsed" -ge 2
# 件数はハードコードせずファイル数から出す（前のケースの残りに左右されないように）
expected_pass=$(find "$tmp" -maxdepth 1 -name 'test-*.sh' | wc -l)
check "serial なテストも件数に入る" grep -qE "pass: $expected_pass 件" <<<"$out"

# serial 宣言は --ci でも効く（ci-skip とは独立した軸）
: >"$tmp/ser.log"
start=$(date +%s)
out=$(TEST_DIR="$tmp" TEST_JOBS=4 bash "$RUNNER" --ci 2>&1)
elapsed=$(($(date +%s) - start))
check "--ci でも serial は直列で走る" test "$elapsed" -ge 2

# 出力順は serial かどうかに関わらずテスト名の昇順
names=$(grep -oE 'test-(par|ser)[0-9]\.sh' <<<"$out")
sorted=$(printf '%s\n' "$names" | sort)
check "serial を混ぜても出力はテスト名の昇順" test "$names" = "$sorted"

# serial なテストの失敗も拾う
make_test test-ser3.sh '# serial: 理由
echo "直列でも読める理由"; exit 1'
out=$(TEST_DIR="$tmp" TEST_JOBS=4 bash "$RUNNER" 2>&1)
rc=$?
check "serial なテストの失敗を検出する" test "$rc" -ne 0
check "serial なテストの出力も見せる" grep -q "直列でも読める理由" <<<"$out"

# ci-skip と serial の両方が付いていたら --ci ではスキップが勝つ
make_test test-ser4.sh '# ci-skip: CIでは無理
# serial: 実環境に依存する
echo ran >"'"$tmp"'/ser4-ran"
exit 0'
rm -f "$tmp/ser4-ran"
out=$(TEST_DIR="$tmp" TEST_JOBS=4 bash "$RUNNER" --ci 2>&1)
check "ci-skip と serial 併記なら --ci ではスキップ" test ! -f "$tmp/ser4-ran"

rm -f "$tmp"/test-par*.sh "$tmp"/test-ser*.sh "$tmp/ser.log" "$tmp/ser4-ran"

# --- 自分自身を対象にしない ---
# run-tests.sh は test-*.sh に一致しない名前でなければ自分を再帰実行してしまう
check "ランナー名が test-*.sh に一致しない" bash -c '[[ "$(basename "'"$RUNNER"'")" != test-* ]]'

# --- 対象が0件 ---
empty=$(mktemp -d)
out=$(TEST_DIR="$empty" bash "$RUNNER" 2>&1)
rc=$?
check "対象0件なら非0で知らせる" test "$rc" -ne 0
rmdir "$empty"

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
