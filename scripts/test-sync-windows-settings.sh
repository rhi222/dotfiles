#!/bin/bash
# scripts/sync-windows-settings.sh のユニットテスト
#
# 実ファイルは Windows 側（/mnt/c）にあるため、テストでは環境変数で全パスを
# 差し替えて一時ディレクトリだけで完結させる。実環境の .wslconfig と
# Windows Terminal の settings.json には一切触れない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/sync-windows-settings.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET が存在しません"
  exit 1
fi

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
  shift
  for line in "$@"; do echo "        $line"; done
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$name"
  else
    ng "$name" "期待: [$expected]" "実際: [$actual]"
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$name"
  else
    ng "$name" "[$needle] を含むべき" "実際: [$haystack]"
  fi
}

assert_rc() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$name"
  else
    ng "$name" "期待 exit: $expected" "実際 exit: $actual"
  fi
}

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

WSLCONFIG_LIVE="$TMPROOT/live/.wslconfig"
WSLCONFIG_REPO="$TMPROOT/repo/wsl/.wslconfig"
WT_LIVE="$TMPROOT/live/wt-settings.json"
WT_REPO="$TMPROOT/repo/windows-terminal/settings.json"
mkdir -p "$TMPROOT/live" "$TMPROOT/repo/wsl" "$TMPROOT/repo/windows-terminal"

run() {
  env \
    WSLCONFIG_LIVE="$WSLCONFIG_LIVE" WSLCONFIG_REPO="$WSLCONFIG_REPO" \
    WT_SETTINGS_LIVE="$WT_LIVE" WT_SETTINGS_REPO="$WT_REPO" \
    bash "$TARGET" "$@" 2>&1
}

# コメント・キー順を保持するか見たいので、あえて整っていない内容にする
WSLCONFIG_SAMPLE='[wsl2]
# 物理32GBのうちWSLに回せるのは約11.5GB
memory=12GB
swap=8GB
processors=6

[experimental]
autoMemoryReclaim=gradual'

# 上位キーをわざと逆順にして、正規化でソートされることを見る
WT_SAMPLE='{"profiles":{"list":[{"name":"Ubuntu","guid":"{affd9aa5-1d57-527e-b847-ac0c816c8512}"}]},"defaultProfile":"{affd9aa5-1d57-527e-b847-ac0c816c8512}","copyOnSelect":true}'

reset_fixtures() {
  printf '%s\n' "$WSLCONFIG_SAMPLE" >"$WSLCONFIG_LIVE"
  printf '%s\n' "$WT_SAMPLE" >"$WT_LIVE"
  rm -f "$WSLCONFIG_REPO" "$WT_REPO"
}

echo "== target の指定 =="
reset_fixtures
out=$(run pull nonexistent)
rc=$?
assert_rc "未知の target はエラー" 1 "$rc"
assert_contains "未知の target を名指しする" "$out" "nonexistent"

reset_fixtures
run pull >/dev/null
if [[ -f "$WSLCONFIG_REPO" && -f "$WT_REPO" ]]; then
  ok "target 省略で両方が取り込まれる"
else
  ng "target 省略で両方が取り込まれる" "wslconfig: $([[ -f $WSLCONFIG_REPO ]] && echo あり || echo なし)" "terminal: $([[ -f $WT_REPO ]] && echo あり || echo なし)"
fi

reset_fixtures
run pull wslconfig >/dev/null
if [[ -f "$WSLCONFIG_REPO" && ! -f "$WT_REPO" ]]; then
  ok "target 指定で片方だけ処理する"
else
  ng "target 指定で片方だけ処理する" "terminal 側まで書いてしまっている"
fi

echo "== pull =="
reset_fixtures
run pull >/dev/null
assert_eq "wslconfig はコメントと順序をそのまま保つ" "$WSLCONFIG_SAMPLE" "$(cat "$WSLCONFIG_REPO")"

expected_wt=$(printf '%s' "$WT_SAMPLE" | jq -S .)
assert_eq "terminal は jq -S で正規化される" "$expected_wt" "$(cat "$WT_REPO")"

out=$(run pull)
assert_contains "2回目は変更なしと言う" "$out" "変更なし"

reset_fixtures
printf 'old\n' >"$WSLCONFIG_REPO"
out=$(run pull wslconfig --dry-run)
assert_eq "--dry-run は書き込まない" "old" "$(cat "$WSLCONFIG_REPO")"
assert_contains "--dry-run と分かる出力" "$out" "dry-run"

echo "== status =="
reset_fixtures
run pull >/dev/null
out=$(run status)
rc=$?
assert_contains "一致していれば一致と言う" "$out" "一致"
assert_rc "一致時は exit 0" 0 "$rc"

printf 'memory=16GB\n' >"$WSLCONFIG_LIVE"
out=$(run status wslconfig)
rc=$?
assert_contains "差分があれば差分ありと言う" "$out" "差分あり"
assert_rc "差分ありでも exit 0（確認コマンドなので）" 0 "$rc"

reset_fixtures
rm -f "$WSLCONFIG_LIVE"
out=$(run status wslconfig)
rc=$?
assert_rc "実ファイルが無ければ status はエラー" 1 "$rc"

echo "== push =="
reset_fixtures
run pull >/dev/null
printf 'memory=16GB\n' >"$WSLCONFIG_LIVE"
out=$(run push wslconfig)
rc=$?
assert_rc "差分ありの push は既定で拒否" 1 "$rc"
assert_eq "拒否時に実ファイルを書き換えない" "memory=16GB" "$(cat "$WSLCONFIG_LIVE")"
assert_contains "pull か --force かを案内する" "$out" "--force"

out=$(run push wslconfig --force)
rc=$?
assert_rc "--force なら成功する" 0 "$rc"
assert_eq "--force で実ファイルを上書きする" "$WSLCONFIG_SAMPLE" "$(cat "$WSLCONFIG_LIVE")"
assert_contains "wslconfig の push は再起動が要ると案内する" "$out" "wsl --shutdown"

reset_fixtures
run pull >/dev/null
rm -f "$WSLCONFIG_LIVE"
out=$(run push wslconfig)
rc=$?
assert_rc "実ファイルが無ければ作成する" 0 "$rc"
assert_eq "作成された内容がリポジトリ版と一致する" "$WSLCONFIG_SAMPLE" "$(cat "$WSLCONFIG_LIVE")"

reset_fixtures
run pull >/dev/null
out=$(run push terminal)
assert_contains "一致していれば push は変更なし" "$out" "変更なし"

echo "== 壊れた入力を伝播させない =="
reset_fixtures
printf 'not json\n' >"$WT_LIVE"
out=$(run pull terminal)
rc=$?
assert_rc "不正JSONの実ファイルは pull で弾く" 1 "$rc"
if [[ ! -f "$WT_REPO" ]]; then
  ok "弾いたときリポジトリ側を書かない"
else
  ng "弾いたときリポジトリ側を書かない" "書かれてしまった: $(cat "$WT_REPO")"
fi

reset_fixtures
run pull terminal >/dev/null
printf 'not json\n' >"$WT_REPO"
out=$(run push terminal --force)
rc=$?
assert_rc "不正JSONのリポジトリ版は push で弾く" 1 "$rc"
assert_eq "弾いたとき実ファイルを書き換えない" "$(printf '%s\n' "$WT_SAMPLE")" "$(cat "$WT_LIVE")"

# .wslconfig は INI。JSON バリデータを通してはいけない
reset_fixtures
out=$(run pull wslconfig)
rc=$?
assert_rc "wslconfig は JSON でなくても通る" 0 "$rc"

echo "---"
echo "pass: $PASS 件 / fail: $FAIL 件 / total: $TOTAL 件"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
