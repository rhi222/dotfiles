#!/bin/bash
# scripts/lib/nippo-paths.sh のユニットテスト
#
# 日報のパス解決を1箇所に閉じ込めているので、ここが壊れると全 nippo skill と
# cron が同時に壊れる。既定値の焼き込み（load 時に $HOME を展開して固定する実装）は
# ~/Obsidian が Windows 側への symlink であるため特に危険で、専用の検査を置いている。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/lib/nippo-paths.sh"

if [[ ! -f "$LIB" ]]; then
  echo "ERROR: $LIB が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  local expected="$1" actual="$2" name="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

# 環境変数をまっさらにしてから読み直す。
# 「読み込み時に一度だけ評価して変数へ焼き込む」実装を検出するため、
# 検査のたびに source し直す。
load_lib() {
  unset NIPPO_DIR NIPPO_VAULT
  # shellcheck disable=SC1090
  source "$LIB"
}

echo "=== root の解決 ==="

load_lib
export NIPPO_DIR="/tmp/nippo-test-dir"
assert_eq "/tmp/nippo-test-dir" "$(nippo_root)" "NIPPO_DIR を指定したらそれが root"
unset NIPPO_DIR

load_lib
export NIPPO_VAULT="/tmp/nippo-test-vault"
assert_eq "/tmp/nippo-test-vault/02_Daily" "$(nippo_root)" "NIPPO_VAULT のみなら <vault>/02_Daily"
unset NIPPO_VAULT

load_lib
export NIPPO_VAULT="/tmp/vault-x"
export NIPPO_DIR="/tmp/dir-x"
assert_eq "/tmp/dir-x" "$(nippo_root)" "両方あれば NIPPO_DIR が優先"
unset NIPPO_VAULT NIPPO_DIR

load_lib
assert_eq "$HOME/Obsidian/02_Daily" "$(nippo_root)" "両方未設定なら \$HOME/Obsidian/02_Daily"

# 既定値の焼き込み検出: $HOME を差し替えたら追随すること
load_lib
_real_home="$HOME"
HOME="/tmp/fake-home"
assert_eq "/tmp/fake-home/Obsidian/02_Daily" "$(nippo_root)" "\$HOME の差し替えに追随する"
HOME="$_real_home"
echo ""

echo "=== 日付の解決 ==="

load_lib
assert_eq "2026-01-05" "$(nippo_resolve_date "2026-01-05")" "引数があればその日付"
assert_eq "$(date +%Y-%m-%d)" "$(nippo_resolve_date "")" "引数が空なら本日"
assert_eq "$(date +%Y-%m-%d)" "$(nippo_resolve_date)" "引数を省略しても本日"
echo ""

echo "=== ファイルパスの組み立て ==="

load_lib
export NIPPO_DIR="/tmp/nd"

assert_eq "/tmp/nd/daily/2026/08/nippo.2026-08-14.md" \
  "$(nippo_daily_file "2026-08-14")" "nippo_daily_file"
assert_eq "/tmp/nd/daily/2026/08" \
  "$(nippo_daily_dir "2026-08-14")" "nippo_daily_dir"
assert_eq "/tmp/nd/daily/2026/01/nippo.2026-01-05.md" \
  "$(nippo_daily_file "2026-01-05")" "nippo_daily_file（月が1桁でもゼロ埋めが落ちない）"
assert_eq "/tmp/nd/daily/2026/01" \
  "$(nippo_daily_dir "2026-01-05")" "nippo_daily_dir（月が1桁）"
assert_eq "/tmp/nd/weekly/2026/nippo-weekly.2026-W33.md" \
  "$(nippo_weekly_file "2026-W33")" "nippo_weekly_file"
assert_eq "/tmp/nd/weekly/2026" \
  "$(nippo_weekly_dir "2026-W33")" "nippo_weekly_dir"
assert_eq "/tmp/nd/config/nippo-goals.md" \
  "$(nippo_goals_file)" "nippo_goals_file"

unset NIPPO_DIR
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
