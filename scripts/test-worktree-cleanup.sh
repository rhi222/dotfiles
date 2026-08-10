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
# --force の説明が実挙動（追跡ファイル限定の dirty 判定）に一致していることを検証する。
# 未追跡のみは --force なしで削除されるため、help がその旨を伝えないと利用者が誤解する。
assert_output_contains "追跡ファイルに未コミット変更" "$output" "--force の説明が追跡ファイル限定であることを示す"
assert_output_contains "未追跡ファイルのみの場合は --force なしでも削除対象" "$output" "未追跡のみは --force なしで削除される旨を伝える"

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
  # SC2123: PATH をあえて潰して gh を見つけられない状態をサブシェル内に閉じて作る。
  # command -v はシェル組み込みなので PATH が空でも動き、実gh経路の失敗を決定的に再現できる。
  # shellcheck disable=SC2123
  PATH="/nonexistent"
  # SC2030: このサブシェル内だけで環境変数を無効化したい（外側の設定に影響させない）ので意図的。
  # shellcheck disable=SC2030
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
# SC2031: 上のサブシェルでの一時的な無効化とは無関係な、別文脈（判定ロジックの検証）での設定。
# 以降のテストが参照する本来の値なので「サブシェルでの変更が失われる」という指摘は当たらない。
# shellcheck disable=SC2031
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

# 未追跡ファイルのみは削除候補（Task 9 で dirty 判定を追跡ファイル限定にした）
p=$(mk_wt w-untracked merged-br3)
: >"$p/untracked-only"
assert_eq "DELETE" "$(classify_worktree "$REPO" "$p" merged-br - "" | cut -f1)" "未追跡ファイルのみ → DELETE"

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

# --- 7. 削除の実行 ---
echo "[7] 削除の実行"
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
git -C "$REPO" worktree add -q "$REPO/.wt/w-gone" -b gone-br
rm -rf "$REPO/.wt/w-gone"

output=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" bash "$CLEANUP" --execute 2>&1)
assert_dir_missing "$REPO/.wt/w-merged" "MERGED の worktree が削除される"
assert_dir_exists "$REPO/.wt/w-open" "OPEN の worktree は残る"
assert_output_lacks "dry-run です" "$output" "--execute では dry-run 案内を出さない"

# ブランチは残す（決定事項）
assert_output_contains "merged-br" "$(git -C "$REPO" branch --list merged-br)" "ブランチは削除しない"

# prunable のメタデータが掃除される
assert_output_lacks "w-gone" "$(git -C "$REPO" worktree list --porcelain)" "prunable のメタデータが prune される"
teardown
echo ""

# --- 8. --force での削除 ---
echo "[8] --force での削除"
setup
STUB="$TEST_DIR/pr-stub.sh"
cat >"$STUB" <<'EOF'
#!/bin/bash
echo "MERGED #1"
EOF
chmod +x "$STUB"

git -C "$REPO" worktree add -q "$REPO/.wt/w-dirty" -b dirty-br
# 追跡ファイルを変更する（Task 9 以降、未追跡のみは SKIP ではなく DELETE になるため）
echo "changed" >>"$REPO/.wt/w-dirty/README.md"

# --force なしでは消えない
output=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" bash "$CLEANUP" --execute 2>&1)
assert_dir_exists "$REPO/.wt/w-dirty" "--force なしでは未コミット変更ありは残る"
assert_output_contains "[SKIP" "$output" "SKIP として報告される"

# --force ありで消える（git 側にも --force を伝播する必要がある）
output=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" bash "$CLEANUP" --execute --force 2>&1)
assert_dir_missing "$REPO/.wt/w-dirty" "--force ありなら未コミット変更ありも削除される"
teardown
echo ""

# --- 9. 未追跡のみは削除候補に含める ---
echo "[9] 未追跡ファイルのみの扱い"
setup
STUB="$TEST_DIR/pr-stub.sh"
cat >"$STUB" <<'EOF'
#!/bin/bash
echo "MERGED #10867"
EOF
chmod +x "$STUB"
export WORKTREE_CLEANUP_PR_STATE_CMD="$STUB"
FORCE=0

# 未追跡ファイルのみ → DELETE（件数を併記）
git -C "$REPO" worktree add -q "$REPO/.wt/w-untracked" -b untracked-br
: >"$REPO/.wt/w-untracked/scratch.md"
mkdir -p "$REPO/.wt/w-untracked/plans"
: >"$REPO/.wt/w-untracked/plans/note.md"
out=$(classify_worktree "$REPO" "$REPO/.wt/w-untracked" untracked-br - "")
assert_eq "DELETE" "$(echo "$out" | cut -f1)" "未追跡のみ → DELETE"
assert_output_contains "未追跡 2 件あり" "$out" "未追跡の件数を理由に併記する"
assert_output_contains "MERGED #10867" "$out" "PR状態も残る"

# 追跡ファイルの変更あり → SKIP（従来どおり）
git -C "$REPO" worktree add -q "$REPO/.wt/w-tracked" -b tracked-br
echo "changed" >>"$REPO/.wt/w-tracked/README.md"
out=$(classify_worktree "$REPO" "$REPO/.wt/w-tracked" tracked-br - "")
assert_eq "SKIP" "$(echo "$out" | cut -f1)" "追跡ファイルの変更 → SKIP"
assert_output_contains "未コミット変更あり" "$out" "SKIPの理由文は従来どおり"

# 追跡変更 + 未追跡の混在 → SKIP（追跡変更が優先）
: >"$REPO/.wt/w-tracked/also-untracked.md"
assert_eq "SKIP" "$(classify_worktree "$REPO" "$REPO/.wt/w-tracked" tracked-br - "" | cut -f1)" "追跡変更と未追跡の混在 → SKIP"

# --force なら追跡変更があっても DELETE
FORCE=1
assert_eq "DELETE" "$(classify_worktree "$REPO" "$REPO/.wt/w-tracked" tracked-br - "" | cut -f1)" "--force なら追跡変更でも DELETE"
FORCE=0

# 完全に clean なら件数併記なし
git -C "$REPO" worktree add -q "$REPO/.wt/w-clean" -b clean-br
out=$(classify_worktree "$REPO" "$REPO/.wt/w-clean" clean-br - "")
assert_eq "DELETE" "$(echo "$out" | cut -f1)" "clean → DELETE"
assert_output_lacks "未追跡" "$out" "cleanなら未追跡の併記なし"

# ヘルパー単体
assert_eq 0 "$(count_untracked "$REPO/.wt/w-clean")" "count_untracked: clean は 0"
assert_eq 2 "$(count_untracked "$REPO/.wt/w-untracked")" "count_untracked: 2件"
assert_eq 0 "$(count_untracked /nonexistent/path)" "count_untracked: 存在しないパスは 0"

unset WORKTREE_CLEANUP_PR_STATE_CMD
teardown
echo ""

# --- 10. 既定の --execute（--force なし）で未追跡のみの MERGED を削除する ---
# 修正1（Critical）の回帰テスト。Task 9 で未追跡のみは --force なしでも DELETE 判定に
# なったが、git worktree remove は未追跡ファイルがあると --force なしで拒否する。
# execute_deletions が常に --force を渡すことで、既定モードでも削除できることを確認する。
echo "[10] 既定の --execute で未追跡のみを削除"
setup
STUB="$TEST_DIR/pr-stub.sh"
cat >"$STUB" <<'EOF'
#!/bin/bash
echo "MERGED #99"
EOF
chmod +x "$STUB"

# clean な MERGED（比較用）と 未追跡のみの MERGED
git -C "$REPO" worktree add -q "$REPO/.wt/w-clean" -b clean-br
git -C "$REPO" worktree add -q "$REPO/.wt/w-untracked" -b untracked-br
: >"$REPO/.wt/w-untracked/scratch.md"
: >"$REPO/.wt/w-untracked/note.md"

# --force を付けずに --execute する
output=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" bash "$CLEANUP" --execute 2>&1)
assert_dir_missing "$REPO/.wt/w-clean" "既定の --execute で clean な MERGED が削除される"
assert_dir_missing "$REPO/.wt/w-untracked" "既定の --execute で未追跡のみの MERGED も削除される"
teardown
echo ""

# --- 11. remove が失敗しても後続を継続し、失敗理由を出力する ---
# 修正2（Important）の回帰テスト。git の stderr を握り潰さず利用者に見せる。
# また1件の削除失敗で後続の worktree 処理を止めない。
echo "[11] remove 失敗時の継続とエラー表示"
setup
STUB="$TEST_DIR/pr-stub.sh"
cat >"$STUB" <<'EOF'
#!/bin/bash
echo "MERGED #99"
EOF
chmod +x "$STUB"

# 失敗させる worktree は専用の親ディレクトリ配下に置き、親を書き込み不可にする。
# 親が a-w だと git worktree remove がディレクトリ削除に失敗する（Permission denied）。
# git worktree list --porcelain はパス昇順で並ぶため、失敗する worktree が
# 成功する worktree より前に処理されるようパス名で順序を固定する
# （a-fail-parent < z-ok）。失敗の「後続」が処理されることを検証するため。
mkdir -p "$REPO/.wt/a-fail-parent"
git -C "$REPO" worktree add -q "$REPO/.wt/a-fail-parent/w-fail" -b fail-br
git -C "$REPO" worktree add -q "$REPO/.wt/z-ok" -b ok-br

chmod a-w "$REPO/.wt/a-fail-parent"
output=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" bash "$CLEANUP" --execute 2>&1)
# 親を書き込み可能に戻す（戻さないと teardown の rm -rf が失敗する）
chmod u+w "$REPO/.wt/a-fail-parent"

assert_output_contains "Permission denied" "$output" "git の失敗理由（stderr）が利用者に見える"
assert_dir_missing "$REPO/.wt/z-ok" "1件失敗しても後続の worktree は削除される（処理継続）"
teardown
echo ""

# --- 12. --force 時に破棄される追跡変更を DELETE 行に併記する ---
# 修正4（Important）の回帰テスト。--force で追跡ファイルの未コミット変更が破棄される
# worktree は、DELETE 行にその旨を併記して見えるようにする。
echo "[12] --force 時の破棄注記"
setup
STUB="$TEST_DIR/pr-stub.sh"
cat >"$STUB" <<'EOF'
#!/bin/bash
echo "MERGED #99"
EOF
chmod +x "$STUB"
export WORKTREE_CLEANUP_PR_STATE_CMD="$STUB"

# 追跡ファイルに未コミット変更がある MERGED
git -C "$REPO" worktree add -q "$REPO/.wt/w-tracked" -b tracked-br
echo "changed" >>"$REPO/.wt/w-tracked/README.md"

# 追跡変更 + 未追跡の混在
git -C "$REPO" worktree add -q "$REPO/.wt/w-both" -b both-br
echo "changed" >>"$REPO/.wt/w-both/README.md"
: >"$REPO/.wt/w-both/scratch.md"

FORCE=1
out=$(classify_worktree "$REPO" "$REPO/.wt/w-tracked" tracked-br - "")
assert_eq "DELETE" "$(echo "$out" | cut -f1)" "--force で追跡変更あり → DELETE"
assert_output_contains "未コミット変更あり・破棄されます" "$out" "追跡変更の破棄を DELETE 行に併記する"

out=$(classify_worktree "$REPO" "$REPO/.wt/w-both" both-br - "")
assert_output_contains "未コミット変更あり・破棄されます" "$out" "混在でも破棄注記を出す"
assert_output_contains "未追跡" "$out" "混在では未追跡の件数も併記する"
FORCE=0

# clean な MERGED は破棄注記を出さない
git -C "$REPO" worktree add -q "$REPO/.wt/w-clean2" -b clean2-br
FORCE=1
out=$(classify_worktree "$REPO" "$REPO/.wt/w-clean2" clean2-br - "")
assert_output_lacks "未コミット変更あり・破棄されます" "$out" "clean なら破棄注記なし"
FORCE=0

unset WORKTREE_CLEANUP_PR_STATE_CMD
teardown
echo ""

# --- 13. サマリの件数表示が実行結果を反映する ---
# --execute で削除したのに「DELETE 候補: N 件」と出ると、まだ候補が残っているように読める。
# また N_DELETE は分類結果なので、削除に失敗しても件数が減らず成功したように見えていた。
# dry-run は「候補」、--execute は「実際に削除できた件数」を出し分けることを検証する。
echo "[13] サマリの件数表示"
setup
STUB="$TEST_DIR/pr-stub.sh"
cat >"$STUB" <<'EOF'
#!/bin/bash
echo "MERGED #99"
EOF
chmod +x "$STUB"

git -C "$REPO" worktree add -q "$REPO/.wt/w-merged" -b merged-br

output=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" bash "$CLEANUP" 2>&1)
assert_output_contains "DELETE 候補: 1 件" "$output" "dry-run は DELETE 候補として件数を出す"
assert_output_lacks "削除       :" "$output" "dry-run では削除件数行を出さない"
assert_output_lacks "DELETED=" "$output" "dry-run の機械可読行に DELETED は出ない"

output=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" bash "$CLEANUP" --execute 2>&1)
assert_output_lacks "DELETE 候補" "$output" "--execute では「候補」と表示しない"
assert_output_contains "削除       : 1 件" "$output" "--execute は実際に削除できた件数を出す"
assert_output_lacks "削除失敗" "$output" "失敗がなければ失敗行は出さない"
assert_output_contains "DELETED=1 DELETE_FAILED=0" "$output" "機械可読行に実削除件数が出る"
teardown

# 削除に失敗した分は成功件数に数えない（失敗の作り方は [11] と同じ）
setup
STUB="$TEST_DIR/pr-stub.sh"
cat >"$STUB" <<'EOF'
#!/bin/bash
echo "MERGED #99"
EOF
chmod +x "$STUB"

mkdir -p "$REPO/.wt/a-fail-parent"
git -C "$REPO" worktree add -q "$REPO/.wt/a-fail-parent/w-fail" -b fail-br
git -C "$REPO" worktree add -q "$REPO/.wt/z-ok" -b ok-br

chmod a-w "$REPO/.wt/a-fail-parent"
output=$(WORKTREE_CLEANUP_ROOTS="$TEST_DIR" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" bash "$CLEANUP" --execute 2>&1)
chmod u+w "$REPO/.wt/a-fail-parent"

assert_output_contains "削除       : 1 件" "$output" "失敗した分は成功件数に含めない"
assert_output_contains "削除失敗   : 1 件" "$output" "失敗件数を表示する"
assert_output_contains "DELETE_CANDIDATES=2" "$output" "分類件数は機械可読行に残る"
assert_output_contains "DELETED=1 DELETE_FAILED=1" "$output" "機械可読行に成功/失敗の内訳が出る"
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
