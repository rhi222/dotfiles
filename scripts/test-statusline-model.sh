#!/bin/bash
# .config/claude/scripts/statusline-model.sh のユニットテスト
#
# ccstatusline の custom-command ウィジェットは stdin に Claude Code の
# statusline JSON を渡し、stdout をそのまま表示する（preserveColors 時は ANSI 保持）。
# ここでは JSON を流し込んで、可視テキストと ANSI エスケープの両方を検証する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../.config/claude/scripts/statusline-model.sh"

if [[ ! -x "$TARGET" ]]; then
  echo "ERROR: $TARGET が実行可能ファイルとして存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

# ANSI エスケープを除去して可視テキストだけを取り出す
strip_ansi() {
  sed -e 's/\x1b\[[0-9;]*m//g'
}

run_target() {
  printf '%s' "$1" | "$TARGET"
}

assert_visible() {
  local name="$1" json="$2" expected="$3"
  local actual
  actual=$(run_target "$json" | strip_ansi)
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "        期待: [$expected]"
    echo "        実際: [$actual]"
  fi
}

assert_contains() {
  local name="$1" json="$2" needle="$3"
  local actual
  actual=$(run_target "$json" | cat -v)
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "        [$needle] を含むべき"
    echo "        実際: [$actual]"
  fi
}

assert_not_contains() {
  local name="$1" json="$2" needle="$3"
  local actual
  actual=$(run_target "$json" | cat -v)
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "        [$needle] を含むべきでない"
    echo "        実際: [$actual]"
  fi
}

FABLE='{"model":{"id":"claude-fable-5","display_name":"Fable 5"}}'
OPUS='{"model":{"id":"claude-opus-5[1m]","display_name":"Opus 5 (1M context)"}}'
SONNET='{"model":{"id":"claude-sonnet-5","display_name":"Sonnet 5"}}'

echo "=== Fable のとき反転バッジを出す ==="
assert_visible "バッジのテキストは ⚡FABLE 5⚡" "$FABLE" '⚡FABLE 5⚡'
# くすんだオリーブ背景(48;5;58) + 淡いカーキ文字(38;5;186) + 太字(1) のバッジ
assert_contains "オリーブ背景の ANSI を含む" "$FABLE" '48;5;58'
assert_contains "カーキ文字の ANSI を含む" "$FABLE" '38;5;186'
assert_contains "リセットで終わる" "$FABLE" '^[[0m'
assert_not_contains "Model: プレフィックスは付けない" "$FABLE" 'Model:'

echo "=== id だけが Fable でもバッジを出す（display_name の表記揺れ対策） ==="
assert_contains "id 前方一致で判定する" \
  '{"model":{"id":"claude-fable-5-20260101","display_name":"Claude 5"}}' '48;5;58'
assert_contains "id の大文字小文字は無視する" \
  '{"model":{"id":"claude-FABLE-5"}}' '48;5;58'

echo "=== display_name だけが Fable でもバッジを出す ==="
assert_contains "display_name 部分一致で判定する" \
  '{"model":{"id":"claude-5-experimental","display_name":"Fable 5 mini"}}' '48;5;58'

echo "=== Fable 以外は従来表示（cyan の Model: <名前>） ==="
assert_visible "Opus は括弧を落として Model: Opus 5" "$OPUS" 'Model: Opus 5'
assert_contains "cyan の ANSI を含む" "$OPUS" '^[[36m'
assert_not_contains "バッジの背景色は使わない" "$OPUS" '48;5;58'
assert_visible "Sonnet も同様" "$SONNET" 'Model: Sonnet 5'
assert_not_contains "opus に fable は含まれない（誤検知しない）" "$OPUS" '48;5;58'

echo "=== フォールバック ==="
assert_visible "display_name が無ければ id を使う" \
  '{"model":{"id":"claude-opus-5"}}' 'Model: claude-opus-5'
assert_visible "model が無ければ何も出さない" '{"workspace":{}}' ''
assert_visible "JSON が壊れていても何も出さない" 'not a json' ''

echo "=== jq が無い環境でも statusline を壊さない ==="
TOTAL=$((TOTAL + 1))
no_jq_raw=$(printf '%s' "$FABLE" | env PATH=/nonexistent "$TARGET" 2>/dev/null)
no_jq_status=$?
no_jq_out=$(printf '%s' "$no_jq_raw" | strip_ansi)
if [[ $no_jq_status -eq 0 && "$no_jq_out" == "Model: ?" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: jq 不在時は Model: ? を返して exit 0"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: jq 不在時は Model: ? を返して exit 0"
  echo "        実際: status=$no_jq_status out=[$no_jq_out]"
fi

echo "=== 出力は1行に収める ==="
TOTAL=$((TOTAL + 1))
lines=$(run_target "$FABLE" | wc -l)
if [[ "$lines" -le 1 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: 改行を含まない"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: 改行を含まない (実際: ${lines}行)"
fi

echo ""
echo "================================"
echo "合計: $TOTAL / PASS: $PASS / FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
