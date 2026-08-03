#!/bin/bash
# worktree-cleanup.sh のユニットテスト
# 一時ディレクトリにfixtureリポジトリとworktreeを作って検証する
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLEANUP="$SCRIPT_DIR/worktree-cleanup.sh"

if [[ ! -f "$CLEANUP" ]]; then
  echo "ERROR: $CLEANUP が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
REPO=""

assert_eq() {
  local expected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name (expected=$expected, got=$actual)"
  fi
}

assert_output_contains() {
  local expected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$actual" | grep -qF "$expected"; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected to contain: $expected"
    echo "    actual: $actual"
  fi
}

assert_output_lacks() {
  local unexpected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$actual" | grep -qF "$unexpected"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected NOT to contain: $unexpected"
    echo "    actual: $actual"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  fi
}

assert_dir_exists() {
  local path="$1" test_name="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -d "$path" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name ($path が存在しない)"
  fi
}

assert_dir_missing() {
  local path="$1" test_name="$2"
  TOTAL=$((TOTAL + 1))
  if [[ ! -d "$path" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name ($path が存在してしまっている)"
  fi
}

teardown() {
  [[ -n "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
  TEST_DIR=""
}

# fixtureリポジトリを作る。worktreeは各テストで必要な分だけ生やす。
setup() {
  TEST_DIR=$(mktemp -d)
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email "test@example.com"
  git -C "$REPO" config user.name "test"
  echo "# fixture" >"$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -qm "init"
}

echo "=== worktree-cleanup.sh テスト ==="
echo ""

# --- 1. CLI表面 ---
echo "[1] CLI表面"
output=$(bash "$CLEANUP" --help 2>&1)
assert_output_contains "usage" "$output" "--help が使い方を表示する"

exit_code=0
output=$(bash "$CLEANUP" --bogus-option 2>&1) || exit_code=$?
assert_eq 1 "$exit_code" "不明オプションは exit 1"
assert_output_contains "Unknown option" "$output" "不明オプション名を報告する"

# sourceしてデフォルト値を確認する（mainは走らない）
# shellcheck source=worktree-cleanup.sh
source "$CLEANUP"
assert_eq 0 "$EXECUTE" "EXECUTE の既定は 0（dry-run）"
assert_eq 0 "$FORCE" "FORCE の既定は 0"
assert_eq 0 "$SHOW_SIZE" "SHOW_SIZE の既定は 0"

parse_args --execute --force --size
assert_eq 1 "$EXECUTE" "--execute で EXECUTE=1"
assert_eq 1 "$FORCE" "--force で FORCE=1"
assert_eq 1 "$SHOW_SIZE" "--size で SHOW_SIZE=1"

assert_eq "1.0G" "$(format_kb 1048576)" "format_kb: 1048576KB → 1.0G"
assert_eq "500M" "$(format_kb 512000)" "format_kb: 512000KB → 500M"
assert_eq "12K" "$(format_kb 12)" "format_kb: 12KB → 12K"

# 存在しないパスは必ず 0 を返す（呼び出し側が $(( )) で加算するため）
assert_eq 0 "$(path_size_kb /nonexistent/path/xyz)" "path_size_kb: 存在しないパスは 0"
echo ""

# --- 2. worktreeメタデータの抽出 ---
echo "[2] worktreeメタデータの抽出"
setup
git -C "$REPO" worktree add -q "$REPO/.wt/normal" -b normal
git -C "$REPO" worktree add -q "$REPO/.wt/lockme" -b lockme
git -C "$REPO" worktree lock --reason "claude session (pid 123)" "$REPO/.wt/lockme"
git -C "$REPO" worktree add -q --detach "$REPO/.wt/det"
git -C "$REPO" worktree add -q "$REPO/.wt/gone" -b gone
rm -rf "$REPO/.wt/gone"
# ディレクトリ名とブランチ名がずれるケース（実環境で発生している）
git -C "$REPO" worktree add -q "$REPO/.wt/dirname-differs" -b actual-branch-name

wt_out=$(list_worktrees "$REPO")

# フィールド区切りのタブは $'\t' で明示する（リテラルタブに依存しない）
TB=$'\t'
assert_output_lacks "${REPO}${TB}main${TB}" "$wt_out" "main worktree は含まれない"
assert_output_contains "$REPO/.wt/normal${TB}normal${TB}-${TB}" "$wt_out" "通常のworktree: flagsは -"
assert_output_contains "$REPO/.wt/lockme${TB}lockme${TB}locked${TB}claude session (pid 123)" "$wt_out" "locked: flagsとdetailを拾う"
assert_output_contains "$REPO/.wt/det${TB}${TB}-${TB}" "$wt_out" "detached: branchは空文字"
assert_output_contains "$REPO/.wt/gone${TB}gone${TB}prunable${TB}" "$wt_out" "prunable: flagsに prunable"
assert_output_contains "$REPO/.wt/dirname-differs${TB}actual-branch-name${TB}-${TB}" "$wt_out" "ブランチ名はディレクトリ名ではなくbranch行から取る"
assert_eq 5 "$(echo "$wt_out" | grep -c .)" "linked worktree は5件"
teardown
echo ""

# --- 3. リポジトリの走査 ---
echo "[3] リポジトリの走査"
setup
# 走査ルート配下に2つ目のリポジトリを作る
REPO2="$TEST_DIR/nested/repo2"
mkdir -p "$REPO2"
git -C "$REPO2" init -q -b main
git -C "$REPO2" config user.email "test@example.com"
git -C "$REPO2" config user.name "test"
echo "x" >"$REPO2/f"
git -C "$REPO2" add f
git -C "$REPO2" commit -qm "init"

repos_out=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" discover_repos)
assert_output_contains "$REPO" "$repos_out" "走査ルート直下のリポジトリを見つける"
assert_output_contains "$REPO2" "$repos_out" "ネストしたリポジトリも見つける"
assert_eq 2 "$(echo "$repos_out" | grep -c .)" "リポジトリは2件"
teardown
echo ""

# --- 4. PR状態の取得 ---
echo "[4] PR状態の取得"
setup

# スタブ: ブランチ名で状態を返す。exit 1 で取得失敗を再現する。
STUB="$TEST_DIR/pr-stub.sh"
cat >"$STUB" <<'EOF'
#!/bin/bash
# $1=repo $2=branch
case "$2" in
  merged-br) echo "MERGED #10737" ;;
  closed-br) echo "CLOSED #99" ;;
  open-br) echo "OPEN #11068" ;;
  nopr-br) echo "NONE" ;;
  broken-br) exit 1 ;;
  *) echo "NONE" ;;
esac
EOF
chmod +x "$STUB"

assert_eq "MERGED #10737" "$(WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" get_pr_state "$REPO" merged-br)" "スタブ経由で MERGED を返す"
assert_eq "CLOSED #99" "$(WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" get_pr_state "$REPO" closed-br)" "スタブ経由で CLOSED を返す"
assert_eq "NONE" "$(WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" get_pr_state "$REPO" nopr-br)" "PRなしは NONE"

exit_code=0
WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" get_pr_state "$REPO" broken-br >/dev/null 2>&1 || exit_code=$?
assert_eq 1 "$exit_code" "取得失敗は非ゼロで return"

# gh が使えない環境では実gh経路が失敗扱いになる。
# PATH を潰して gh を見つけられない状態を作り、環境非依存で決定的に検証する
# （command -v はシェル組み込みなので PATH が空でも動作する）。
exit_code=0
(
  PATH="/nonexistent"
  WORKTREE_CLEANUP_PR_STATE_CMD=""
  get_pr_state "$REPO" any-br
) >/dev/null 2>&1 || exit_code=$?
assert_eq 1 "$exit_code" "gh が見つからない環境では非ゼロで return"
teardown
echo ""

# --- 5. 判定ロジック ---
echo "[5] 判定ロジック"
setup
STUB="$TEST_DIR/pr-stub.sh"
cat >"$STUB" <<'EOF'
#!/bin/bash
case "$2" in
  merged-br) echo "MERGED #10737" ;;
  closed-br) echo "CLOSED #99" ;;
  open-br) echo "OPEN #11068" ;;
  nopr-br) echo "NONE" ;;
  broken-br) exit 1 ;;
  *) echo "NONE" ;;
esac
EOF
chmod +x "$STUB"
export WORKTREE_CLEANUP_PR_STATE_CMD="$STUB"

# clean な worktree を作るヘルパー
mk_wt() {
  local name="$1" branch="$2"
  git -C "$REPO" worktree add -q "$REPO/.wt/$name" -b "$branch"
  echo "$REPO/.wt/$name"
}

FORCE=0

p=$(mk_wt w-merged merged-br)
assert_eq "DELETE" "$(classify_worktree "$REPO" "$p" merged-br - "" | cut -f1)" "MERGED → DELETE"
assert_output_contains "MERGED #10737" "$(classify_worktree "$REPO" "$p" merged-br - "")" "理由にPR番号が入る"

p=$(mk_wt w-closed closed-br)
assert_eq "DELETE" "$(classify_worktree "$REPO" "$p" closed-br - "" | cut -f1)" "CLOSED → DELETE"

p=$(mk_wt w-open open-br)
assert_eq "KEEP" "$(classify_worktree "$REPO" "$p" open-br - "" | cut -f1)" "OPEN → KEEP"

p=$(mk_wt w-nopr nopr-br)
assert_eq "KEEP" "$(classify_worktree "$REPO" "$p" nopr-br - "" | cut -f1)" "PRなし → KEEP"

p=$(mk_wt w-broken broken-br)
assert_eq "KEEP" "$(classify_worktree "$REPO" "$p" broken-br - "" | cut -f1)" "PR状態の取得失敗 → KEEP"
assert_output_contains "取得に失敗" "$(classify_worktree "$REPO" "$p" broken-br - "")" "失敗理由を出す"

# 未コミット変更あり（MERGEDでもSKIP）
p=$(mk_wt w-dirty2 merged-br2)
echo "changed" >>"$p/README.md"
assert_eq "SKIP" "$(classify_worktree "$REPO" "$p" merged-br - "" | cut -f1)" "未コミット変更 → SKIP"
FORCE=1
assert_eq "DELETE" "$(classify_worktree "$REPO" "$p" merged-br - "" | cut -f1)" "--force なら未コミット変更でも DELETE"
FORCE=0

# 未追跡ファイルのみでもSKIP
p=$(mk_wt w-untracked merged-br3)
: >"$p/untracked-only"
assert_eq "SKIP" "$(classify_worktree "$REPO" "$p" merged-br - "" | cut -f1)" "未追跡ファイルのみ → SKIP"

# locked は PR状態より優先してSKIP
p=$(mk_wt w-locked merged-br4)
assert_eq "SKIP" "$(classify_worktree "$REPO" "$p" merged-br locked "claude session (pid 123)" | cut -f1)" "locked → SKIP（MERGEDでも）"
assert_output_contains "locked" "$(classify_worktree "$REPO" "$p" merged-br locked "claude session (pid 123)")" "理由に locked を出す"

# prunable は削除ではなく prune
assert_eq "PRUNE" "$(classify_worktree "$REPO" "$REPO/.wt/nonexistent" gone prunable "gitdir file points to non-existent location" | cut -f1)" "prunable → PRUNE"

# detached は判定不能
git -C "$REPO" worktree add -q --detach "$REPO/.wt/w-det"
assert_eq "SKIP" "$(classify_worktree "$REPO" "$REPO/.wt/w-det" "" - "" | cut -f1)" "detached → SKIP"
assert_output_contains "detached" "$(classify_worktree "$REPO" "$REPO/.wt/w-det" "" - "")" "理由に detached を出す"

unset WORKTREE_CLEANUP_PR_STATE_CMD
teardown
echo ""

# --- 6. レポート出力とサマリ ---
echo "[6] レポート出力とサマリ"
setup
STUB="$TEST_DIR/pr-stub.sh"
cat >"$STUB" <<'EOF'
#!/bin/bash
case "$2" in
  merged-br) echo "MERGED #10737" ;;
  open-br) echo "OPEN #11068" ;;
  *) echo "NONE" ;;
esac
EOF
chmod +x "$STUB"

git -C "$REPO" worktree add -q "$REPO/.wt/w-merged" -b merged-br
git -C "$REPO" worktree add -q "$REPO/.wt/w-open" -b open-br
git -C "$REPO" worktree add -q "$REPO/.wt/w-locked" -b locked-br
git -C "$REPO" worktree lock --reason "claude session" "$REPO/.wt/w-locked"
git -C "$REPO" worktree add -q "$REPO/.wt/w-gone" -b gone-br
rm -rf "$REPO/.wt/w-gone"

# dry-run のエンドツーエンド実行
output=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" bash "$CLEANUP" 2>&1)
assert_output_contains "[DELETE]" "$output" "DELETE行が出る"
assert_output_contains "merged-br" "$output" "DELETE対象のブランチ名が出る"
assert_output_contains "MERGED #10737" "$output" "PR番号が出る"
assert_output_contains "[KEEP" "$output" "KEEP行が出る"
assert_output_contains "[SKIP" "$output" "SKIP行が出る"
assert_output_contains "[PRUNE" "$output" "PRUNE行が出る"
assert_output_contains "DELETE_CANDIDATES=1" "$output" "機械可読サマリのDELETE件数"
assert_output_contains "PRUNE=1" "$output" "機械可読サマリのPRUNE件数"
assert_output_contains "SKIP=1" "$output" "機械可読サマリのSKIP件数"
assert_output_contains "KEEP=1" "$output" "機械可読サマリのKEEP件数"
assert_output_contains "dry-run" "$output" "dry-runの案内が出る"

# dry-run は何も削除しない
assert_dir_exists "$REPO/.wt/w-merged" "dry-runではDELETE候補を削除しない"

# --size は解放見込みを出す
output=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" bash "$CLEANUP" --size 2>&1)
assert_output_contains "解放見込み" "$output" "--size で解放見込みを表示する"
teardown
echo ""

# --- 6b. detached worktree の分類（空フィールド畳み込みの回帰） ---
echo "[6b] detached worktree の分類"
setup
STUB="$TEST_DIR/pr-stub.sh"
cat >"$STUB" <<'EOF'
#!/bin/bash
echo "NONE"
EOF
chmod +x "$STUB"

# 素の detached（ディレクトリあり）と detached+prunable（ディレクトリ消失）
git -C "$REPO" worktree add -q --detach "$REPO/.wt/w-detached"
git -C "$REPO" worktree add -q --detach "$REPO/.wt/w-det-gone"
rm -rf "$REPO/.wt/w-det-gone"

output=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" bash "$CLEANUP" 2>&1)
assert_output_contains "[SKIP" "$output" "detached worktree は SKIP"
assert_output_contains "detached HEAD" "$output" "detached の理由に detached HEAD が出る"
assert_output_contains "[PRUNE" "$output" "detached+prunable は PRUNE"
# バグ時は空 branch が畳まれ flags 値(prunable)を branch として拾い KEEP(PR なし)になっていた
assert_output_lacks "PR なし" "$output" "detached が branch にフラグ値を拾って KEEP に誤分類されない"
assert_output_contains "detached 1" "$output" "SKIP内訳の detached が正しく1件数えられる"
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
