#!/bin/bash
# sync-claude-settings.sh のユニットテスト
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC="$SCRIPT_DIR/sync-claude-settings.sh"

if [[ ! -f "$SYNC" ]]; then
  echo "ERROR: $SYNC が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
LIVE=""
REPO=""

setup() {
  TEST_DIR=$(mktemp -d)
  LIVE="$TEST_DIR/live/settings.json"
  REPO="$TEST_DIR/repo/settings.json"
  mkdir -p "$TEST_DIR/live" "$TEST_DIR/repo"
  export CLAUDE_SETTINGS_LIVE="$LIVE"
  export CLAUDE_SETTINGS_REPO="$REPO"
}

teardown() {
  rm -rf "$TEST_DIR"
  unset CLAUDE_SETTINGS_LIVE
  unset CLAUDE_SETTINGS_REPO
}

ok() {
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

ng() {
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
  [[ -n "${2:-}" ]] && echo "    $2"
}

assert_exit() {
  local expected="$1" actual="$2" name="$3" out="${4:-}"
  if [[ "$actual" -eq "$expected" ]]; then
    ok "$name"
  else
    ng "$name" "expected exit=$expected, got exit=$actual / output: $out"
  fi
}

assert_contains() {
  local expected="$1" actual="$2" name="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    ok "$name"
  else
    ng "$name" "expected to contain [$expected], got [$actual]"
  fi
}

assert_file_eq() {
  local expected_file="$1" actual_file="$2" name="$3"
  if diff -q "$expected_file" "$actual_file" >/dev/null 2>&1; then
    ok "$name"
  else
    ng "$name" "$(diff "$expected_file" "$actual_file" | head -5)"
  fi
}

assert_json_eq() {
  local a="$1" b="$2" name="$3"
  if diff -q <(jq -S . "$a") <(jq -S . "$b") >/dev/null 2>&1; then
    ok "$name"
  else
    ng "$name" "$(diff <(jq -S . "$a") <(jq -S . "$b") | head -5)"
  fi
}

run_sync() {
  local out exit_code=0
  out=$(bash "$SYNC" "$@" 2>&1) || exit_code=$?
  printf '%s\n---EXIT---%s' "$out" "$exit_code"
}

out_of() { echo "${1%%---EXIT---*}"; }
exit_of() { echo "${1##*---EXIT---}"; }

# キー順をわざと崩した（が意味は同じ）設定
UNSORTED='{"theme":"dark","env":{"B":"2","A":"1"},"model":"opus"}'
SORTED_FILE=""
make_sorted_expectation() {
  SORTED_FILE="$TEST_DIR/expected.json"
  echo "$1" | jq -S . >"$SORTED_FILE"
}

echo "=== sync-claude-settings.sh テスト ==="
echo ""

# =============================================================================
# pull: live -> repo
# =============================================================================
echo "[1] pull: liveの内容をrepoへ取り込む"

setup
echo "$UNSORTED" >"$LIVE"
echo '{"theme":"light"}' >"$REPO"
r=$(run_sync pull)
assert_exit 0 "$(exit_of "$r")" "pullはexit 0" "$(out_of "$r")"
assert_json_eq "$LIVE" "$REPO" "repoがliveと同じ内容になる"
assert_contains "更新" "$(out_of "$r")" "更新した旨を報告する"
teardown

echo ""
echo "[2] pull: キー順を正規化して書き込む"

setup
echo "$UNSORTED" >"$LIVE"
echo '{}' >"$REPO"
make_sorted_expectation "$UNSORTED"
run_sync pull >/dev/null
assert_file_eq "$SORTED_FILE" "$REPO" "jq -S 相当に正規化される"
teardown

echo ""
echo "[3] pull: 既に正規化済みで一致していれば書き込まない"

setup
echo "$UNSORTED" | jq -S . >"$LIVE"
echo "$UNSORTED" | jq -S . >"$REPO"
touch -t "202001010000.00" "$REPO"
r=$(run_sync pull)
assert_exit 0 "$(exit_of "$r")" "一致時もexit 0" "$(out_of "$r")"
assert_contains "変更なし" "$(out_of "$r")" "変更なしと報告する"
if [[ "$(stat -c %Y "$REPO")" == "$(date -d '2020-01-01 00:00:00' +%s)" ]]; then
  ok "repoファイルに書き込まない（mtime据え置き）"
else
  ng "repoファイルに書き込まない（mtime据え置き）" "mtimeが更新された"
fi
teardown

echo ""
echo "[4] pull: 意味は同じでも未正規化なら書き直す"

setup
echo "$UNSORTED" >"$LIVE"
echo "$UNSORTED" >"$REPO" # 未正規化
touch -t "202001010000.00" "$REPO"
r=$(run_sync pull)
assert_contains "更新" "$(out_of "$r")" "正規化のために書き直す"
make_sorted_expectation "$UNSORTED"
assert_file_eq "$SORTED_FILE" "$REPO" "正規化された内容になる"
teardown

echo ""
echo "[5] pull: liveが無い / 不正JSON なら repo を触らずに失敗"

setup
echo '{"theme":"light"}' >"$REPO"
cp "$REPO" "$TEST_DIR/before.json"
r=$(run_sync pull)
assert_exit 1 "$(exit_of "$r")" "liveが無ければexit 1" "$(out_of "$r")"
assert_file_eq "$TEST_DIR/before.json" "$REPO" "repoは変更されない"

echo 'これはJSONではない' >"$LIVE"
r=$(run_sync pull)
assert_exit 1 "$(exit_of "$r")" "不正JSONならexit 1" "$(out_of "$r")"
assert_file_eq "$TEST_DIR/before.json" "$REPO" "不正JSONでもrepoは変更されない"
teardown

echo ""
echo "[6] pull --dry-run: 書き込まずに差分だけ報告"

setup
echo "$UNSORTED" >"$LIVE"
echo '{"theme":"light"}' >"$REPO"
cp "$REPO" "$TEST_DIR/before.json"
r=$(run_sync pull --dry-run)
assert_exit 0 "$(exit_of "$r")" "--dry-runはexit 0" "$(out_of "$r")"
assert_file_eq "$TEST_DIR/before.json" "$REPO" "--dry-runでは書き込まない"
teardown

# =============================================================================
# push: repo -> live
# =============================================================================
echo ""
echo "[7] push: liveが無ければ作成する"

setup
echo "$UNSORTED" >"$REPO"
NESTED="$TEST_DIR/newhome/.claude/settings.json"
export CLAUDE_SETTINGS_LIVE="$NESTED"
r=$(run_sync push)
assert_exit 0 "$(exit_of "$r")" "live未作成でもexit 0" "$(out_of "$r")"
if [[ -f "$NESTED" ]]; then
  ok "親ディレクトリごとliveを作成する"
  assert_json_eq "$REPO" "$NESTED" "repoの内容が入る"
else
  ng "親ディレクトリごとliveを作成する" "作成されていない"
fi
teardown

echo ""
echo "[8] push: 一致していれば何もしない"

setup
echo "$UNSORTED" | jq -S . >"$REPO"
echo "$UNSORTED" | jq -S . >"$LIVE"
touch -t "202001010000.00" "$LIVE"
r=$(run_sync push)
assert_exit 0 "$(exit_of "$r")" "一致時はexit 0" "$(out_of "$r")"
assert_contains "変更なし" "$(out_of "$r")" "変更なしと報告する"
teardown

echo ""
echo "[9] push: 差分があれば拒否する（--force なしでは上書きしない）"

setup
echo '{"theme":"dark"}' >"$REPO"
echo '{"theme":"light"}' >"$LIVE"
cp "$LIVE" "$TEST_DIR/before.json"
r=$(run_sync push)
assert_exit 1 "$(exit_of "$r")" "差分ありはexit 1" "$(out_of "$r")"
assert_file_eq "$TEST_DIR/before.json" "$LIVE" "liveは変更されない"
assert_contains "pull" "$(out_of "$r")" "pullを促す案内を出す"
teardown

echo ""
echo "[10] push --force: 差分があっても上書きする"

setup
echo '{"theme":"dark"}' >"$REPO"
echo '{"theme":"light"}' >"$LIVE"
r=$(run_sync push --force)
assert_exit 0 "$(exit_of "$r")" "--forceはexit 0" "$(out_of "$r")"
assert_json_eq "$REPO" "$LIVE" "liveがrepoの内容で上書きされる"
teardown

echo ""
echo "[11] push: repoが無い / 不正JSON なら live を触らずに失敗"

setup
echo '{"theme":"light"}' >"$LIVE"
cp "$LIVE" "$TEST_DIR/before.json"
r=$(run_sync push --force)
assert_exit 1 "$(exit_of "$r")" "repoが無ければexit 1" "$(out_of "$r")"
assert_file_eq "$TEST_DIR/before.json" "$LIVE" "liveは変更されない"

echo 'これはJSONではない' >"$REPO"
r=$(run_sync push --force)
assert_exit 1 "$(exit_of "$r")" "不正JSONならexit 1" "$(out_of "$r")"
assert_file_eq "$TEST_DIR/before.json" "$LIVE" "不正JSONでもliveは変更されない"
teardown

# =============================================================================
# status
# =============================================================================
echo ""
echo "[12] status: 差分を報告するだけで両方とも書き換えない"

setup
echo '{"theme":"dark"}' >"$REPO"
echo '{"theme":"light"}' >"$LIVE"
cp "$REPO" "$TEST_DIR/repo-before.json"
cp "$LIVE" "$TEST_DIR/live-before.json"
r=$(run_sync status)
assert_exit 0 "$(exit_of "$r")" "statusはexit 0" "$(out_of "$r")"
assert_contains "差分" "$(out_of "$r")" "差分ありと報告する"
assert_file_eq "$TEST_DIR/repo-before.json" "$REPO" "repoを書き換えない"
assert_file_eq "$TEST_DIR/live-before.json" "$LIVE" "liveを書き換えない"

echo '{"theme":"dark"}' >"$LIVE"
r=$(run_sync status)
assert_contains "一致" "$(out_of "$r")" "一致と報告する"
teardown

# =============================================================================
# 引数
# =============================================================================
echo ""
echo "[13] 引数エラー"

setup
echo '{}' >"$LIVE"
echo '{}' >"$REPO"
r=$(run_sync)
assert_exit 2 "$(exit_of "$r")" "引数なしはexit 2" "$(out_of "$r")"
r=$(run_sync bogus)
assert_exit 2 "$(exit_of "$r")" "未知のサブコマンドはexit 2" "$(out_of "$r")"
assert_contains "使い方" "$(out_of "$r")" "使い方を表示する"
teardown

# =============================================================================
# マスク: このリポジトリは public なので、社内プラグインの設定を入れない。
# 実ファイルを正とする同期は保ったまま、機密エントリだけを落とす。
# =============================================================================
echo ""
echo "=== マスク: pull は機密エントリをリポジトリに入れない ==="
setup
mask_patterns="$TEST_DIR/patterns.txt"
printf 'secretcorp\n' >"$mask_patterns"
export SECRET_PATTERNS="$mask_patterns"

cat >"$LIVE" <<'EOF'
{
  "enabledPlugins": {
    "cdk@secretcorp-marketplace": true,
    "superpowers@claude-plugins-official": true
  },
  "extraKnownMarketplaces": {
    "secretcorp-marketplace": {"source": {"source": "git", "url": "git@github.com:secretcorp/mp.git"}},
    "anthropic-agent-skills": {"source": {"repo": "anthropics/skills", "source": "github"}}
  },
  "theme": "dark"
}
EOF

r=$(run_sync pull)
assert_exit 0 "$(exit_of "$r")" "マスクありでも pull は成功する" "$(out_of "$r")"
if grep -q secretcorp "$REPO"; then
  ng "pull がリポジトリから機密エントリを落とす" "$(grep -n secretcorp "$REPO")"
else
  ok "pull がリポジトリから機密エントリを落とす"
fi
if jq -e '.enabledPlugins["superpowers@claude-plugins-official"]' "$REPO" >/dev/null; then
  ok "pull が機密でないエントリを残す"
else
  ng "pull が機密でないエントリを残す" "$(cat "$REPO")"
fi
if jq -e '.theme == "dark"' "$REPO" >/dev/null; then
  ok "pull がマスク対象外のキーを保持する"
else
  ng "pull がマスク対象外のキーを保持する" "$(cat "$REPO")"
fi
teardown

echo ""
echo "=== マスク: push は実ファイルの機密エントリを消さない ==="
setup
mask_patterns="$TEST_DIR/patterns.txt"
printf 'secretcorp\n' >"$mask_patterns"
export SECRET_PATTERNS="$mask_patterns"

cat >"$LIVE" <<'EOF'
{
  "enabledPlugins": {
    "cdk@secretcorp-marketplace": true,
    "superpowers@claude-plugins-official": true
  },
  "extraKnownMarketplaces": {
    "secretcorp-marketplace": {"source": {"source": "git", "url": "git@github.com:secretcorp/mp.git"}}
  },
  "theme": "dark"
}
EOF
cat >"$REPO" <<'EOF'
{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true
  },
  "extraKnownMarketplaces": {},
  "theme": "light"
}
EOF

r=$(run_sync push --force)
assert_exit 0 "$(exit_of "$r")" "push --force が成功する" "$(out_of "$r")"
if jq -e '.enabledPlugins["cdk@secretcorp-marketplace"]' "$LIVE" >/dev/null; then
  ok "push が実ファイルの機密エントリを保持する"
else
  ng "push が実ファイルの機密エントリを保持する" "$(cat "$LIVE")"
fi
if jq -e '.extraKnownMarketplaces["secretcorp-marketplace"]' "$LIVE" >/dev/null; then
  ok "push が実ファイルの機密marketplaceを保持する"
else
  ng "push が実ファイルの機密marketplaceを保持する" "$(cat "$LIVE")"
fi
if jq -e '.theme == "light"' "$LIVE" >/dev/null; then
  ok "push がリポジトリ側の変更を反映する"
else
  ng "push がリポジトリ側の変更を反映する" "$(cat "$LIVE")"
fi
teardown

echo ""
echo "=== マスク: status と push はマスク後どうしで比較する ==="
setup
mask_patterns="$TEST_DIR/patterns.txt"
printf 'secretcorp\n' >"$mask_patterns"
export SECRET_PATTERNS="$mask_patterns"

cat >"$LIVE" <<'EOF'
{
  "enabledPlugins": {"cdk@secretcorp-marketplace": true},
  "theme": "dark"
}
EOF
cat >"$REPO" <<'EOF'
{
  "enabledPlugins": {},
  "theme": "dark"
}
EOF

r=$(run_sync status)
assert_contains "一致" "$(out_of "$r")" "機密エントリの差だけなら status は一致と判定する"
# push は差分ありと誤認して拒否してはいけない（機密は元々リポジトリに無いため）
r=$(run_sync push)
assert_exit 0 "$(exit_of "$r")" "機密エントリの差だけなら push は拒否しない" "$(out_of "$r")"
teardown
unset SECRET_PATTERNS

echo ""
echo "=== マスク: 辞書が無ければマスクしない ==="
setup
export SECRET_PATTERNS="$TEST_DIR/no-such-file.txt"
cat >"$LIVE" <<'EOF'
{"enabledPlugins": {"cdk@secretcorp-marketplace": true}}
EOF
r=$(run_sync pull)
assert_exit 0 "$(exit_of "$r")" "辞書が無くても pull は成功する" "$(out_of "$r")"
if grep -q secretcorp "$REPO"; then
  ok "辞書が無ければマスクせずそのまま取り込む"
else
  ng "辞書が無ければマスクせずそのまま取り込む" "$(cat "$REPO")"
fi
teardown
unset SECRET_PATTERNS

# =============================================================================
# アトミック書き込み: 一時ファイル + rename で書く。中断時に書きかけを残さず、
# 既存ファイルのパーミッションを引き継ぐ。
# =============================================================================
echo ""
echo "=== アトミック書き込み: 中間ファイルを残さない ==="
setup
echo "$UNSORTED" >"$LIVE"
echo '{"theme":"light"}' >"$REPO"
run_sync pull >/dev/null
leftover=$(find "$TEST_DIR/repo" -name '.settings-sync.*' 2>/dev/null)
if [[ -z "$leftover" ]]; then
  ok "pull 後に一時ファイル(.settings-sync.*)が残らない"
else
  ng "pull 後に一時ファイル(.settings-sync.*)が残らない" "$leftover"
fi
teardown

echo ""
echo "=== アトミック書き込み: 既存ファイルのパーミッションを引き継ぐ ==="
setup
echo '{"theme":"dark"}' >"$REPO"
echo '{"theme":"light"}' >"$LIVE"
chmod 600 "$LIVE"
run_sync push --force >/dev/null
mode=$(stat -c %a "$LIVE")
if [[ "$mode" == "600" ]]; then
  ok "push --force の上書きで実ファイルの 600 を保つ"
else
  ng "push --force の上書きで実ファイルの 600 を保つ" "mode=$mode"
fi
teardown

echo ""
echo "=== アトミック書き込み: 新規作成は umask に従う（リダイレクトと同じ） ==="
setup
echo "$UNSORTED" >"$REPO"
NEW="$TEST_DIR/newhome/.claude/settings.json"
export CLAUDE_SETTINGS_LIVE="$NEW"
expected_mode=$(printf '%03o' "$((0666 & ~0$(umask)))")
run_sync push >/dev/null
mode=$(stat -c %a "$NEW")
if [[ "$mode" == "${expected_mode#0}" || "$mode" == "$expected_mode" ]]; then
  ok "新規作成のパーミッションが umask 由来（$expected_mode）"
else
  ng "新規作成のパーミッションが umask 由来（$expected_mode）" "mode=$mode"
fi
teardown

# =============================================================================
echo ""
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
