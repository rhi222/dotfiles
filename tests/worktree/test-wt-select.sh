#!/bin/bash
# fish関数 __wt_main_path / __wt_format_rows のユニットテスト
#
# `__wt_format_rows` は `git wt` の出力（ヘッダ除去済み）を fzf 表示用に整形する純粋関数。
# git-wt バイナリも fzf も要らないよう、入力はフィクスチャ文字列で与える。
# `__wt_main_path` だけは git に問い合わせるので一時リポジトリを作って検証する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FUNC_DIR="$(cd "$REPO_ROOT/.config/fish/my/functions" && pwd)"
MAIN_PATH="$FUNC_DIR/__wt_main_path.fish"
FORMAT_ROWS="$FUNC_DIR/__wt_format_rows.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi
for f in "$MAIN_PATH" "$FORMAT_ROWS"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f が存在しません"
    exit 1
  fi
done

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
REPO=""

setup_repo() {
  TEST_DIR=$(mktemp -d)
  # mktemp が /tmp -> /private/tmp のようなsymlinkを返す環境でも
  # git が返す実パスと比較できるようにする
  TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email "test@example.com"
  git -C "$REPO" config user.name "test"
  git -C "$REPO" commit -q --allow-empty -m init
}

teardown_repo() {
  rm -rf "$TEST_DIR"
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

# フィクスチャを __wt_format_rows に流し、指定パスを含む行のタグだけを取り出す
tag_of() {
  local fixture="$1" main_path="$2" needle="$3"
  fish -c "
    source '$FORMAT_ROWS'
    printf '%s\n' '$fixture' | __wt_format_rows '$main_path'
  " 2>&1 | grep -F "$needle" | sed -E 's/^\*? *\[([^]]*)\].*/\1/'
}

echo "=== __wt_format_rows / __wt_main_path テスト ==="
echo ""

# `git wt` の出力（ヘッダ除去済み）を模したフィクスチャ。
# メインworktree・.wt配下・.claude/worktrees配下・それ以外を1つずつ含む。
FIXTURE='* /data/repos/app                                    main             e653469
  /data/repos/app/.wt/ALPHADEV-4941-refund           refund-branch    6d49684
  /data/repos/app/.claude/worktrees/issue-162-mail    fix/issue-162    e051e05
  /tmp/adhoc-tree                                     spike            aaaaaaa'

# --- 1. Claude Code の worktree を claude と判定する（今回のバグの回帰） ---
echo "[1] .claude/worktrees 配下"
assert_eq "claude" "$(tag_of "$FIXTURE" "/data/repos/app" ".claude/worktrees/issue-162-mail")" \
  "Claude Codeのworktreeは claude"
echo ""

# --- 2. 既存の判定を壊していない ---
echo "[2] 既存の分類"
assert_eq "main" "$(tag_of "$FIXTURE" "/data/repos/app" "/data/repos/app e653469")" \
  "メインworktreeは main"
assert_eq ".wt" "$(tag_of "$FIXTURE" "/data/repos/app" ".wt/ALPHADEV-4941-refund")" \
  "git wt の worktree は .wt"
assert_eq "wt" "$(tag_of "$FIXTURE" "/data/repos/app" "/tmp/adhoc-tree")" \
  "それ以外のリンクworktreeは wt"
echo ""

# --- 3. メインworktreeのパスに .wt が含まれても main（旧ヒューリスティックの誤判定） ---
echo "[3] パス文字列に釣られない"
DOTWT_FIXTURE='* /data/repos/.wt-sandbox/app       main       e653469
  /data/repos/.wt-sandbox/app/.wt/feat-x  feat-x  6d49684'
assert_eq "main" "$(tag_of "$DOTWT_FIXTURE" "/data/repos/.wt-sandbox/app" "/data/repos/.wt-sandbox/app e653469")" \
  "パスに .wt を含むメインworktreeも main"
assert_eq ".wt" "$(tag_of "$DOTWT_FIXTURE" "/data/repos/.wt-sandbox/app" "/.wt/feat-x")" \
  "その配下の .wt worktree は .wt"
echo ""

# --- 4. wt / wtd が使うフィールド抽出と互換であること ---
# wt.fish:   branch = ($1 == "*") ? $3 : $2
# wtd.fish:  path   = ($1 == "*") ? $4 : $3
echo "[4] wt/wtd とのフィールド互換"
rows=$(fish -c "source '$FORMAT_ROWS'; printf '%s\n' '$FIXTURE' | __wt_format_rows /data/repos/app" 2>&1)

marked=$(echo "$rows" | grep -F '* ')
assert_eq "main" "$(echo "$marked" | awk '{if ($1 == "*") print $3; else print $2}')" \
  "マーカー行から branch を取れる"
assert_eq "/data/repos/app" "$(echo "$marked" | awk '{if ($1 == "*") print $4; else print $3}')" \
  "マーカー行から path を取れる"

unmarked=$(echo "$rows" | grep -F '.claude/worktrees/issue-162-mail')
assert_eq "fix/issue-162" "$(echo "$unmarked" | awk '{if ($1 == "*") print $3; else print $2}')" \
  "非マーカー行から branch を取れる"
assert_eq "/data/repos/app/.claude/worktrees/issue-162-mail" \
  "$(echo "$unmarked" | awk '{if ($1 == "*") print $4; else print $3}')" \
  "非マーカー行から path を取れる"
echo ""

# --- 5. main_path が取れなかった場合も落ちない ---
echo "[5] main_path が空"
out=$(fish -c "source '$FORMAT_ROWS'; printf '%s\n' '$FIXTURE' | __wt_format_rows ''; echo rc=\$status" 2>&1)
assert_eq "rc=0" "$(echo "$out" | tail -1)" "空文字でもエラーにしない"
assert_eq "4" "$(echo "$out" | grep -cF '[')" "全行を出力する"
echo ""

# --- 6. __wt_main_path: メインworktreeを返す ---
echo "[6] __wt_main_path"
setup_repo
assert_eq "$REPO" "$(fish -c "source '$MAIN_PATH'; cd '$REPO'; __wt_main_path" 2>&1)" \
  "メインworktree内ではそのパスを返す"

git -C "$REPO" worktree add -q "$REPO/.wt/feat-x" -b feat-x
assert_eq "$REPO" "$(fish -c "source '$MAIN_PATH'; cd '$REPO/.wt/feat-x'; __wt_main_path" 2>&1)" \
  "リンクworktree内でもメインworktreeのパスを返す"
teardown_repo

out=$(fish -c "source '$MAIN_PATH'; cd /; __wt_main_path; echo rc=\$status" 2>&1)
assert_eq "rc=1" "$(echo "$out" | tail -1)" "gitリポジトリ外では return 1"
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
