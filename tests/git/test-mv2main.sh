#!/bin/bash
# fish関数 mv2main / mvuntracked の characterization test
#
# どちらも破壊的（mv/cp する）ので、実挙動を固定する回帰テストを置く。
# fzf も対話も無く、実物の git worktree・mv・cp をそのまま使えるので end-to-end で回す。
#
# 関数は autoload させる。テスト用の $XDG_CONFIG_HOME/fish/functions に本物の
# functions ディレクトリを symlink で見せることで、mvuntracked が内部で spawn する
# `fish -c 'mv2main $argv'` の子プロセスからも mv2main が解決できるようにする。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FUNC_DIR="$(cd "$REPO_ROOT/.config/fish/my/functions" && pwd)"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi
for f in mv2main.fish mvuntracked.fish; do
  if [[ ! -f "$FUNC_DIR/$f" ]]; then
    echo "ERROR: $FUNC_DIR/$f が存在しません"
    exit 1
  fi
done

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
CFG=""
REPO="" # 本体ワークツリー（= worktree list の先頭）
WT=""   # 作業ワークツリー
WT2=""  # 取り違え検出用の別ワークツリー

setup() {
  TEST_DIR=$(mktemp -d)
  TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
  CFG="$TEST_DIR/cfg"
  mkdir -p "$CFG/fish"
  ln -s "$FUNC_DIR" "$CFG/fish/functions"

  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email "test@example.com"
  git -C "$REPO" config user.name "test"
  git -C "$REPO" commit -q --allow-empty -m init
  WT="$TEST_DIR/wt1"
  git -C "$REPO" worktree add -q "$WT" -b feat-x
}

setup_second_worktree() {
  WT2="$TEST_DIR/wt2"
  git -C "$REPO" worktree add -q "$WT2" -b feat-y
}

teardown() {
  rm -rf "$TEST_DIR"
  WT2=""
}

# 隔離した fish で、指定した cwd から fish コード片を実行する。
#   run_fish <cwd> <fish-code>
run_fish() {
  local cwd="$1" code="$2"
  env XDG_CONFIG_HOME="$CFG" fish -c "cd '$cwd'; $code" 2>&1
}

assert_eq() {
  local expected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected to contain: $needle"
    echo "    actual:              $haystack"
  fi
}

assert_file_exists() {
  local path="$1" test_name="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -e "$path" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name ($path が無い)"
  fi
}

assert_file_missing() {
  local path="$1" test_name="$2"
  TOTAL=$((TOTAL + 1))
  if [[ ! -e "$path" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name ($path が残っている)"
  fi
}

echo "=== mv2main / mvuntracked テスト ==="
echo ""

# =============================================================================
# mv2main
# =============================================================================

# --- 1. ワークツリーから本体へ mv する ---
echo "[1] mv2main（通常 mv）"
setup
echo hi >"$WT/foo.txt"
run_fish "$WT" 'mv2main foo.txt' >/dev/null
assert_file_exists "$REPO/foo.txt" "本体ワークツリーへ移動する"
assert_file_missing "$WT/foo.txt" "元のワークツリーから消える"
teardown
echo ""

# --- 2. --dry-run は実際には mv しない ---
echo "[2] mv2main（--dry-run）"
setup
echo hi >"$WT/bar.txt"
out=$(run_fish "$WT" 'mv2main --dry-run bar.txt')
assert_file_exists "$WT/bar.txt" "dry-run では元ファイルが残る"
assert_file_missing "$REPO/bar.txt" "dry-run では本体に作られない"
assert_contains "$out" "[dry-run]" "[dry-run] 表示を出す"
assert_contains "$out" "mv -v" "mv コマンドを表示する"
teardown
echo ""

# --- 3. --copy は元を残す ---
echo "[3] mv2main（--copy）"
setup
echo hi >"$WT/baz.txt"
run_fish "$WT" 'mv2main --copy baz.txt' >/dev/null
assert_file_exists "$WT/baz.txt" "copy では元ファイルが残る"
assert_file_exists "$REPO/baz.txt" "本体にも作られる"
teardown
echo ""

# --- 4. ネストしたパスは本体側のディレクトリを作る ---
echo "[4] mv2main（ネストしたパス）"
setup
mkdir -p "$WT/sub/dir"
echo hi >"$WT/sub/dir/x.txt"
run_fish "$WT" 'mv2main sub/dir/x.txt' >/dev/null
assert_file_exists "$REPO/sub/dir/x.txt" "本体側に destdir を作って移動する"
assert_file_missing "$WT/sub/dir/x.txt" "元から消える"
teardown
echo ""

# --- 5. 先頭の ./ を剥がす ---
echo "[5] mv2main（./ 剥がし）"
setup
echo hi >"$WT/qux.txt"
run_fish "$WT" 'mv2main ./qux.txt' >/dev/null
assert_file_exists "$REPO/qux.txt" "./ 付きでも本体直下へ移動する"
assert_file_missing "$REPO/./qux.txt/qux.txt" "余計な階層を作らない"
teardown
echo ""

# --- 6. スペース入りファイル名 ---
echo "[6] mv2main（スペース入り）"
setup
printf 'x' >"$WT/a b.txt"
run_fish "$WT" 'mv2main "a b.txt"' >/dev/null
assert_file_exists "$REPO/a b.txt" "スペース入りでも移動する"
assert_file_missing "$WT/a b.txt" "元から消える"
teardown
echo ""

# --- 7. 本体ワークツリーからは no-op ---
echo "[7] mv2main（本体からは何もしない）"
setup
echo hi >"$REPO/inmain.txt"
out=$(run_fish "$REPO" 'mv2main inmain.txt; echo rc=$status')
assert_contains "$out" "already in the main worktree" "既に本体だと伝える"
assert_eq "rc=0" "$(echo "$out" | tail -1)" "0 を返す"
assert_file_exists "$REPO/inmain.txt" "ファイルは動かさない"
teardown
echo ""

# --- 8. 存在しないパスはスキップして続行 ---
echo "[8] mv2main（存在しないパス）"
setup
out=$(run_fish "$WT" 'mv2main nope.txt')
assert_contains "$out" "Not found under current worktree" "見つからない旨を出す"
assert_file_missing "$REPO/nope.txt" "本体に作らない"
teardown
echo ""

# --- 9. 別ワークツリーへ取り違えない（宛先は常に本体） ---
echo "[9] mv2main（worktree 取り違え防止）"
setup
setup_second_worktree
echo hi >"$WT2/z.txt"
run_fish "$WT2" 'mv2main z.txt' >/dev/null
assert_file_exists "$REPO/z.txt" "第2ワークツリーからでも本体へ移動する"
assert_file_missing "$WT/z.txt" "別のワークツリーには入れない"
teardown
echo ""

# --- 10. 引数なしは使い方を出して return 2 ---
echo "[10] mv2main（引数なし）"
setup
out=$(run_fish "$WT" 'mv2main; echo rc=$status')
assert_contains "$out" "Usage:" "使い方を表示する"
assert_eq "rc=2" "$(echo "$out" | tail -1)" "return 2"
teardown
echo ""

# =============================================================================
# mvuntracked
# =============================================================================

# --- 11. 未追跡ファイルをまとめて本体へ移す ---
echo "[11] mvuntracked（未追跡をまとめて移動）"
setup
echo a >"$WT/u1.txt"
echo b >"$WT/u2.txt"
run_fish "$WT" 'mvuntracked' >/dev/null
assert_file_exists "$REPO/u1.txt" "u1 を移動する"
assert_file_exists "$REPO/u2.txt" "u2 を移動する"
assert_file_missing "$WT/u1.txt" "u1 が元から消える"
teardown
echo ""

# --- 12. 追跡済みファイルは動かさない（選別ミス防止） ---
echo "[12] mvuntracked（追跡済みは対象外）"
setup
echo tracked >"$WT/keep.txt"
git -C "$WT" add keep.txt
git -C "$WT" commit -q -m add-keep
echo u >"$WT/moveme.txt"
run_fish "$WT" 'mvuntracked' >/dev/null
assert_file_exists "$WT/keep.txt" "追跡済みファイルは残す"
assert_file_missing "$REPO/keep.txt" "追跡済みは本体へ移さない"
assert_file_exists "$REPO/moveme.txt" "未追跡だけ移す"
teardown
echo ""

# --- 13. gitignore 対象は除外（--exclude-standard） ---
echo "[13] mvuntracked（ignore 対象は除外）"
setup
echo 'ignored.txt' >"$WT/.gitignore"
echo x >"$WT/ignored.txt"
echo y >"$WT/normal.txt"
run_fish "$WT" 'mvuntracked' >/dev/null
assert_file_exists "$WT/ignored.txt" "ignore 対象は動かさない"
assert_file_missing "$REPO/ignored.txt" "ignore 対象を本体へ移さない"
assert_file_exists "$REPO/normal.txt" "通常の未追跡は移す"
teardown
echo ""

# --- 14. スペース入りの未追跡ファイル ---
echo "[14] mvuntracked（スペース入り）"
setup
printf 'x' >"$WT/a b.txt"
run_fish "$WT" 'mvuntracked' >/dev/null
assert_file_exists "$REPO/a b.txt" "スペース入りでも移動する"
assert_file_missing "$WT/a b.txt" "元から消える"
teardown
echo ""

# --- 15. --dry-run を mv2main へ転送する ---
echo "[15] mvuntracked（--dry-run 転送）"
setup
echo x >"$WT/d.txt"
out=$(run_fish "$WT" 'mvuntracked --dry-run')
assert_file_exists "$WT/d.txt" "dry-run では動かさない"
assert_file_missing "$REPO/d.txt" "dry-run では本体に作らない"
assert_contains "$out" "[dry-run]" "[dry-run] 表示が出る（フラグが転送されている）"
teardown
echo ""

# =============================================================================
echo "=== 結果 ==="
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
echo ""
if [[ "$FAIL" -gt 0 ]]; then
  echo "テスト失敗"
  exit 1
else
  echo "全テスト成功"
  exit 0
fi
