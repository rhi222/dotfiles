#!/bin/bash
# lib/notify-windows-toast.sh のユニットテスト。
#
# BurntToast モジュールの有無の判定は PowerShell 側（1プロセス内）で行っている。
# Import-Module に実測10秒かかるため、bash 側から別プロセスで discovery すると
# 通知1回のコストが倍になる。そのため bash から検証できるのは
# 「powershell.exe に渡すコマンド文字列が cmdlet をガードしているか」までで、
# モジュール実体の分岐は実機（BurntToast 未導入の端末）で確認する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/lib/notify-windows-toast.sh"

if [[ ! -f "$LIB" ]]; then
  echo "ERROR: $LIB が存在しません"
  exit 1
fi

# shellcheck source=/dev/null
source "$LIB"
set +e

PASS=0
FAIL=0
TOTAL=0

assert_contains() {
  local expected="$1" actual="$2" name="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$actual" | grep -qF -- "$expected"; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected to contain: [$expected]"
    echo "    actual:              [$actual]"
  fi
}

assert_eq() {
  local expected="$1" actual="$2" name="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected: [$expected]"
    echo "    actual:   [$actual]"
  fi
}

TEST_DIR="$(mktemp -d)"
STUB_BIN="$TEST_DIR/bin"
mkdir -p "$STUB_BIN"
# powershell.exe のスタブ。受け取った -Command 文字列をログに落とすだけ。
cat >"$STUB_BIN/powershell.exe" <<'EOF'
#!/bin/bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -Command)
      shift
      printf '%s' "$1" >>"$PS_LOG"
      ;;
  esac
  shift
done
exit 0
EOF
chmod +x "$STUB_BIN/powershell.exe"

echo "[1] cmdlet をガードしてから呼ぶ"
PS_LOG="$TEST_DIR/ps.log"
export PS_LOG
# 実機の ~/.config/claude/hooks/claude-icon.png を拾わないよう既定を無効化する。
# [1]〜[4] はアイコン以外の契約を見るため。
export WINDOWS_TOAST_ICON="$TEST_DIR/none.png"
: >"$PS_LOG"
exit_code=0
PATH="$STUB_BIN:$PATH" send_windows_toast "タイトル" "本文" >/dev/null 2>&1 || exit_code=$?
cmd="$(cat "$PS_LOG")"
assert_eq 0 "$exit_code" "成功する"
assert_contains "BurntToast" "$cmd" "BurntToast を参照する"
assert_contains "Get-Module -ListAvailable -Name BurntToast" "$cmd" \
  "モジュールの有無を先に確認する"
assert_contains "New-BurntToastNotification" "$cmd" "cmdlet を呼ぶ"
assert_contains "タイトル" "$cmd" "タイトルを渡す"
assert_contains "本文" "$cmd" "本文を渡す"

# ガードが cmdlet より前に現れること。順序が逆だと CommandNotFound が出る。
guard_pos="$(awk 'BEGIN{ n=index(ARGV[1], "Get-Module"); print n }' "$cmd")"
cmdlet_pos="$(awk 'BEGIN{ n=index(ARGV[1], "New-BurntToastNotification"); print n }' "$cmd")"
TOTAL=$((TOTAL + 1))
if [[ "$guard_pos" -gt 0 && "$cmdlet_pos" -gt 0 && "$guard_pos" -lt "$cmdlet_pos" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: ガードが cmdlet より前にある"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: ガードが cmdlet より前にある (guard=$guard_pos cmdlet=$cmdlet_pos)"
fi

echo ""
echo "[2] シングルクォートのエスケープ"
: >"$PS_LOG"
PATH="$STUB_BIN:$PATH" send_windows_toast "it's" "don't" >/dev/null 2>&1
cmd="$(cat "$PS_LOG")"
assert_contains "it''s" "$cmd" "タイトルの ' を '' にする"
assert_contains "don''t" "$cmd" "本文の ' を '' にする"

echo ""
echo "[3] icon 指定あり"
: >"$PS_LOG"
icon="$TEST_DIR/icon.png"
touch "$icon"
PATH="$STUB_BIN:$PATH" send_windows_toast "T" "M" "$icon" >/dev/null 2>&1
cmd="$(cat "$PS_LOG")"
assert_contains "-AppLogo" "$cmd" "AppLogo を渡す"
assert_contains "Get-Module -ListAvailable -Name BurntToast" "$cmd" \
  "icon 経路でもガードする"

echo ""
echo "[4] 存在しない icon パスは icon なし扱い"
: >"$PS_LOG"
PATH="$STUB_BIN:$PATH" send_windows_toast "T" "M" "$TEST_DIR/missing.png" >/dev/null 2>&1
cmd="$(cat "$PS_LOG")"
TOTAL=$((TOTAL + 1))
if ! echo "$cmd" | grep -qF -- "AppLogo"; then
  PASS=$((PASS + 1))
  echo "  PASS: AppLogo を渡さない"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: AppLogo を渡さない"
fi

echo ""
echo "[5] 既定アイコン（第3引数の省略時）"
default_icon="$TEST_DIR/default-icon.png"
touch "$default_icon"

# 省略時は既定アイコンを AppLogo に渡す。daily-update と herdr-restore は
# 第3引数を渡していないので、既定が無いとこの2経路だけアイコン無しになる。
: >"$PS_LOG"
PATH="$STUB_BIN:$PATH" WINDOWS_TOAST_ICON="$default_icon" \
  send_windows_toast "T" "M" >/dev/null 2>&1
cmd="$(cat "$PS_LOG")"
assert_contains "-AppLogo" "$cmd" "省略時も AppLogo を渡す"
assert_contains "default-icon.png" "$cmd" "既定アイコンを使う"

# 明示指定は既定より優先する
: >"$PS_LOG"
explicit_icon="$TEST_DIR/explicit-icon.png"
touch "$explicit_icon"
PATH="$STUB_BIN:$PATH" WINDOWS_TOAST_ICON="$default_icon" \
  send_windows_toast "T" "M" "$explicit_icon" >/dev/null 2>&1
cmd="$(cat "$PS_LOG")"
assert_contains "explicit-icon.png" "$cmd" "明示指定が既定より優先される"
TOTAL=$((TOTAL + 1))
if ! echo "$cmd" | grep -qF -- "default-icon.png"; then
  PASS=$((PASS + 1))
  echo "  PASS: 既定アイコンは使われない"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: 既定アイコンは使われない"
fi

# 既定アイコンの実体が無ければ AppLogo を渡さない（アイコン未配置の端末）
: >"$PS_LOG"
PATH="$STUB_BIN:$PATH" WINDOWS_TOAST_ICON="$TEST_DIR/no-such-icon.png" \
  send_windows_toast "T" "M" >/dev/null 2>&1
cmd="$(cat "$PS_LOG")"
TOTAL=$((TOTAL + 1))
if ! echo "$cmd" | grep -qF -- "AppLogo"; then
  PASS=$((PASS + 1))
  echo "  PASS: 既定アイコンが無ければ AppLogo を渡さない"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: 既定アイコンが無ければ AppLogo を渡さない"
fi
assert_contains "New-BurntToastNotification" "$cmd" "アイコン無しでも通知は出す"

rm -rf "$TEST_DIR"

echo ""
echo "=== 結果 ==="
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo "テスト失敗"
  exit 1
fi
echo "全テスト成功"
