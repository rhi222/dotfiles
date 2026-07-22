#!/bin/bash
# worktree-init.sh のユニットテスト
# 一時ディレクトリにfixtureリポジトリとworktreeを作って検証する
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WT_INIT="$SCRIPT_DIR/worktree-init.sh"

if [[ ! -x "$WT_INIT" ]]; then
  echo "ERROR: $WT_INIT が存在しないか実行権限がありません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
REPO=""
WT=""

# fixtureリポジトリを作成する
#   .gitignore: .env* と node_modules/ を無視（.env.example は除外）
#   gitignore対象: .env, packages/app/.env.local, node_modules/pkg/.env
#   tracked:      .env.example, README.md
setup() {
  TEST_DIR=$(mktemp -d)
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email "test@example.com"
  git -C "$REPO" config user.name "test"
  printf '.env*\n!.env.example\nnode_modules/\n' >"$REPO/.gitignore"
  echo "# fixture" >"$REPO/README.md"
  echo "EXAMPLE=1" >"$REPO/.env.example"
  git -C "$REPO" add .gitignore README.md .env.example
  git -C "$REPO" commit -qm "init"
  echo "SECRET=main" >"$REPO/.env"
  mkdir -p "$REPO/packages/app"
  echo "APP=1" >"$REPO/packages/app/.env.local"
  mkdir -p "$REPO/node_modules/pkg"
  echo "NM=1" >"$REPO/node_modules/pkg/.env"
}

# fixtureにworktreeを追加する
add_worktree() {
  WT="$REPO/.wt/feat-x"
  git -C "$REPO" worktree add -q "$WT" -b feat-x
}

teardown() {
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
    echo "  FAIL: $test_name (expected=$expected, got=$actual)"
  fi
}

assert_file_exists() {
  local path="$1" test_name="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$path" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name ($path が存在しない)"
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
    echo "  FAIL: $test_name ($path が存在してしまっている)"
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

echo "=== worktree-init.sh テスト ==="
echo ""

# --- 1. 非gitディレクトリはエラー ---
echo "[1] 非gitディレクトリ"
TEST_DIR=$(mktemp -d)
exit_code=0
output=$("$WT_INIT" "$TEST_DIR" 2>&1) || exit_code=$?
assert_eq 1 "$exit_code" "非gitディレクトリはexit 1"
assert_output_contains "error" "$output" "エラーメッセージを含む"
teardown
echo ""

# --- 2. メインworktreeで実行はエラー ---
echo "[2] メインworktree"
setup
exit_code=0
output=$("$WT_INIT" "$REPO" 2>&1) || exit_code=$?
assert_eq 1 "$exit_code" "メインworktreeはexit 1"
assert_output_contains "error" "$output" "エラーメッセージを含む"
teardown
echo ""

# --- 3. .env系のコピー ---
echo "[3] .env系のコピー"
setup
add_worktree
exit_code=0
output=$("$WT_INIT" "$WT" 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "正常終了はexit 0"
assert_file_exists "$WT/.env" ".env がコピーされる"
assert_file_exists "$WT/packages/app/.env.local" "サブディレクトリの .env.local がコピーされる"
assert_file_missing "$WT/node_modules/pkg/.env" "node_modules配下はコピーされない"
assert_eq "SECRET=main" "$(cat "$WT/.env")" "コピー内容が一致する"
teardown
echo ""

# --- 4. trackedファイルはコピー対象外 ---
echo "[4] trackedファイル"
setup
add_worktree
# .env.example はworktree作成時点でgitからチェックアウト済み。
# worktree-init が「コピーした」と報告しないことを確認する
output=$("$WT_INIT" "$WT" 2>&1)
TOTAL=$((TOTAL + 1))
if echo "$output" | grep -qF "copy: .env.example"; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: .env.example はコピー対象外のはず"
else
  PASS=$((PASS + 1))
  echo "  PASS: .env.example はコピー対象外"
fi
teardown
echo ""

# --- 5. 冪等性: 既存ファイルは上書きしない ---
echo "[5] 冪等性"
setup
add_worktree
echo "SECRET=wt-local" >"$WT/.env"
exit_code=0
output=$("$WT_INIT" "$WT" 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "既存ありでもexit 0"
assert_eq "SECRET=wt-local" "$(cat "$WT/.env")" "既存の .env は上書きされない"
assert_output_contains "skip" "$output" "skipが出力される"
teardown
echo ""

# --- 6. lockファイル判定（dry-run） ---
echo "[6] lockファイル判定"
setup
touch "$REPO/pnpm-lock.yaml"
git -C "$REPO" add pnpm-lock.yaml && git -C "$REPO" commit -qm "add lockfile"
add_worktree
output=$("$WT_INIT" --dry-run "$WT" 2>&1)
assert_output_contains "pnpm install" "$output" "pnpm-lock.yaml → pnpm install"
teardown

setup
touch "$REPO/package-lock.json"
git -C "$REPO" add package-lock.json && git -C "$REPO" commit -qm "add lockfile"
add_worktree
output=$("$WT_INIT" --dry-run "$WT" 2>&1)
assert_output_contains "npm ci" "$output" "package-lock.json → npm ci"
teardown

setup
touch "$REPO/yarn.lock"
git -C "$REPO" add yarn.lock && git -C "$REPO" commit -qm "add lockfile"
add_worktree
output=$("$WT_INIT" --dry-run "$WT" 2>&1)
assert_output_contains "yarn install" "$output" "yarn.lock → yarn install"
teardown

setup
add_worktree
output=$("$WT_INIT" --dry-run "$WT" 2>&1)
assert_output_contains "skip" "$output" "lockファイルなし → skip"
teardown
echo ""

# --- 7. dry-runは実ファイルを作らない ---
echo "[7] dry-run"
setup
add_worktree
output=$("$WT_INIT" --dry-run "$WT" 2>&1)
assert_file_missing "$WT/.env" "dry-runでは .env をコピーしない"
assert_output_contains "[dry-run]" "$output" "[dry-run] 表示を含む"
teardown
echo ""

# --- 8. 固有スクリプトが存在すれば実行される ---
echo "[8] 固有スクリプト実行"
setup
git -C "$REPO" remote add origin "git@github.com:acme/widget.git"
add_worktree
WT_INIT_D="$TEST_DIR/wt-init.d"
mkdir -p "$WT_INIT_D/github.com/acme"
cat >"$WT_INIT_D/github.com/acme/widget.sh" <<EOF
#!/usr/bin/env bash
echo "CUSTOM_RAN target=\$1"
touch "\$1/.custom-marker"
EOF
exit_code=0
output=$(WORKTREE_INIT_D="$WT_INIT_D" "$WT_INIT" "$WT" 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "固有スクリプトありでもexit 0"
assert_output_contains "CUSTOM_RAN" "$output" "固有スクリプトが実行される"
assert_file_exists "$WT/.custom-marker" "固有スクリプトの副作用が反映される"
assert_output_contains "target=$WT" "$output" "第1引数にworktreeパスが渡る"
teardown
echo ""

# --- 9. 固有スクリプトが無ければ共通処理のみ ---
echo "[9] 固有スクリプトなし"
setup
git -C "$REPO" remote add origin "git@github.com:acme/other.git"
add_worktree
WT_INIT_D="$TEST_DIR/wt-init.d"
mkdir -p "$WT_INIT_D"
exit_code=0
output=$(WORKTREE_INIT_D="$WT_INIT_D" "$WT_INIT" "$WT" 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "固有スクリプトなしでもexit 0"
assert_output_contains "custom: skip" "$output" "スクリプトなしはskip表示"
teardown
echo ""

# --- 10. origin未設定はskip ---
echo "[10] origin未設定"
setup
add_worktree
WT_INIT_D="$TEST_DIR/wt-init.d"
mkdir -p "$WT_INIT_D"
exit_code=0
output=$(WORKTREE_INIT_D="$WT_INIT_D" "$WT_INIT" "$WT" 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "origin未設定でもexit 0"
assert_output_contains "custom: skip" "$output" "origin未設定はskip表示"
teardown
echo ""

# --- 11. dry-runでは固有スクリプトを実行しない ---
echo "[11] dry-run 固有スクリプト"
setup
git -C "$REPO" remote add origin "git@github.com:acme/widget.git"
add_worktree
WT_INIT_D="$TEST_DIR/wt-init.d"
mkdir -p "$WT_INIT_D/github.com/acme"
cat >"$WT_INIT_D/github.com/acme/widget.sh" <<EOF
#!/usr/bin/env bash
touch "\$1/.custom-marker"
EOF
output=$(WORKTREE_INIT_D="$WT_INIT_D" "$WT_INIT" --dry-run "$WT" 2>&1)
assert_file_missing "$WT/.custom-marker" "dry-runでは固有スクリプトを実行しない"
assert_output_contains "[dry-run] custom:" "$output" "[dry-run] custom: 表示を含む"
teardown
echo ""

# --- 12. origin URL正規化の網羅（同一キーへ解決） ---
echo "[12] origin URL正規化"
for url in \
  "git@github.com:acme/widget.git" \
  "https://github.com/acme/widget.git" \
  "https://github.com/acme/widget" \
  "ssh://git@github.com/acme/widget.git"; do
  setup
  git -C "$REPO" remote add origin "$url"
  add_worktree
  WT_INIT_D="$TEST_DIR/wt-init.d"
  mkdir -p "$WT_INIT_D/github.com/acme"
  cat >"$WT_INIT_D/github.com/acme/widget.sh" <<EOF
#!/usr/bin/env bash
echo "CUSTOM_RAN"
EOF
  output=$(WORKTREE_INIT_D="$WT_INIT_D" "$WT_INIT" "$WT" 2>&1) || true
  assert_output_contains "CUSTOM_RAN" "$output" "正規化: $url"
  teardown
done
echo ""

# --- 13. 固有スクリプトが失敗しても全体は成功扱い ---
echo "[13] 固有スクリプト失敗の分離"
setup
git -C "$REPO" remote add origin "git@github.com:acme/widget.git"
add_worktree
WT_INIT_D="$TEST_DIR/wt-init.d"
mkdir -p "$WT_INIT_D/github.com/acme"
cat >"$WT_INIT_D/github.com/acme/widget.sh" <<EOF
#!/usr/bin/env bash
echo "before-fail"
exit 3
EOF
exit_code=0
output=$(WORKTREE_INIT_D="$WT_INIT_D" "$WT_INIT" "$WT" 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "固有スクリプト失敗でも worktree-init は exit 0"
assert_output_contains "warning" "$output" "失敗時は warning を出力する"
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
