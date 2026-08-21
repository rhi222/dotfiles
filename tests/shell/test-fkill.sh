#!/bin/bash
# fish関数 fkill / __fkill_extract_pids の characterization test
#
# fkill は `ps aux | fzf | awk '{print $2}'` で選んだ行から PID を取り出し kill -TERM する。
# PID 抽出ロジックを __fkill_extract_pids に切り出したので、その正しさ（複数選択・空選択・
# ヘッダ相当行）を単体で検証する。fkill 本体は fzf を stub、kill を関数で捕まえて、
# 「選択が空なら kill しない」「選択があれば PID 群に TERM を送る」ことを確認する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FUNC_DIR="$(cd "$REPO_ROOT/.config/fish/my/functions" && pwd)"
FKILL="$FUNC_DIR/fkill.fish"
EXTRACT="$FUNC_DIR/__fkill_extract_pids.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi
for f in "$FKILL" "$EXTRACT"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f が存在しません"
    exit 1
  fi
done

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
STUB_DIR=""
KILL_LOG=""

setup() {
  TEST_DIR=$(mktemp -d)
  TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
  STUB_DIR="$TEST_DIR/bin"
  KILL_LOG="$TEST_DIR/kill.log"
  mkdir -p "$STUB_DIR"

  # fzf stub。stdin は捨て、FZF_STUB_OUT をそのまま返す（--header-lines で
  # ヘッダは既に除かれた「選択行」を模す）。空選択は FZF_STUB_OUT 未設定で表す。
  cat >"$STUB_DIR/fzf" <<'STUB'
#!/bin/bash
cat >/dev/null
if [[ -n "${FZF_STUB_OUT:-}" ]]; then
  printf '%s\n' "$FZF_STUB_OUT"
fi
exit "${FZF_STUB_RC:-0}"
STUB
  chmod +x "$STUB_DIR/fzf"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# fkill を隔離実行する。kill は関数で捕まえ、実プロセスへ送らない。
run_fkill() {
  env PATH="$STUB_DIR:$PATH" \
    FZF_STUB_OUT="${FZF_STUB_OUT:-}" \
    FZF_STUB_RC="${FZF_STUB_RC:-0}" \
    KILL_LOG="$KILL_LOG" \
    fish --no-config -c "
      function kill; echo \$argv >>\$KILL_LOG; end
      source '$EXTRACT'
      source '$FKILL'
      fkill
      echo rc=\$status
    " 2>&1
}

# __fkill_extract_pids を stdin 付きで実行する。
run_extract() {
  local input="$1"
  printf '%s' "$input" | fish --no-config -c "source '$EXTRACT'; __fkill_extract_pids" 2>&1
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

echo "=== fkill テスト ==="
echo ""

# =============================================================================
# __fkill_extract_pids
# =============================================================================

# --- 1. 1行から PID（2列目）を取り出す ---
echo "[1] __fkill_extract_pids（単一行）"
assert_eq "1234" "$(run_extract 'alice 1234 0.0 0.1 100 200 ? S 10:00 0:00 vim')" \
  "ps aux 形式の2列目を返す"
echo ""

# --- 2. 複数行 → 複数 PID ---
echo "[2] __fkill_extract_pids（複数行）"
input=$'alice 1234 0.0 0.1 ? S 10:00 0:00 vim\nbob 5678 0.0 0.1 ? S 10:01 0:00 node'
assert_eq $'1234\n5678' "$(run_extract "$input")" "各行の2列目を返す"
echo ""

# --- 3. 空入力 → 空 ---
echo "[3] __fkill_extract_pids（空入力）"
assert_eq "" "$(run_extract '')" "空入力は空を返す"
echo ""

# =============================================================================
# fkill 本体
# =============================================================================

# --- 4. 選択があれば PID 群へ TERM を送る ---
echo "[4] fkill（複数選択で kill）"
setup
export FZF_STUB_OUT=$'alice 1234 0.0 0.1 ? S 10:00 0:00 vim\nbob 5678 0.0 0.1 ? S 10:01 0:00 node'
out=$(run_fkill)
unset FZF_STUB_OUT
assert_eq "rc=0" "$(echo "$out" | tail -1)" "0 を返す"
assert_contains "$(cat "$KILL_LOG" 2>&1)" "-TERM 1234 5678" "選択した PID 群に -TERM を送る"
teardown
echo ""

# --- 5. 空選択なら kill しない ---
echo "[5] fkill（空選択）"
setup
# FZF_STUB_OUT 未設定 = 何も選ばずキャンセル
out=$(run_fkill)
assert_eq "rc=0" "$(echo "$out" | tail -1)" "0 を返す"
assert_eq "0" "$([[ -f "$KILL_LOG" ]] && wc -l <"$KILL_LOG" || echo 0)" "kill を一度も呼ばない"
teardown
echo ""

# --- 6. 単一選択 ---
echo "[6] fkill（単一選択）"
setup
export FZF_STUB_OUT='alice 4242 0.0 0.1 ? S 10:00 0:00 vim'
out=$(run_fkill)
unset FZF_STUB_OUT
assert_contains "$(cat "$KILL_LOG" 2>&1)" "-TERM 4242" "単一 PID に -TERM を送る"
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
