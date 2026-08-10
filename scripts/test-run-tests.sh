#!/bin/bash
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
