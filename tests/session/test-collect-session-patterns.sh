#!/bin/bash
# .config/claude/scripts/collect-session-patterns.sh のユニットテスト
#
# 「スキル利用頻度」は nippo-weekly のスキル化候補の材料になる。
# /model のような組み込みコマンドが最多に居座ると、毎週同じ指摘が出続けるので集計から外す。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)/.config/claude/scripts/collect-session-patterns.sh"

PASS=0
FAIL=0
TOTAL=0

check() {
  local name="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@"; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
  fi
}

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.claude"

now_ms=$(($(date +%s) * 1000))
{
  echo "{\"display\":\"/model\",\"timestamp\":$now_ms,\"project\":\"/p/a\"}"
  echo "{\"display\":\"/model opus\",\"timestamp\":$now_ms,\"project\":\"/p/a\"}"
  echo "{\"display\":\"/nippo-add かいし\",\"timestamp\":$now_ms,\"project\":\"/p/a\"}"
  echo "{\"display\":\"日報つくって\",\"timestamp\":$now_ms,\"project\":\"/p/a\"}"
} >"$TMP_HOME/.claude/history.jsonl"

OUT="$(HOME="$TMP_HOME" DAYS=7 bash "$TARGET" 2>&1)"

echo "=== スキル利用頻度 ==="
check "/model を集計しない（引数なし・ありとも）" bash -c '! grep -q "^  /model:" <<<"$1"' _ "$OUT"
check "/model をスキルコマンド数に数えない" grep -q "スキルコマンド: 1$" <<<"$OUT"
check "通常のスキルは集計する" grep -q "^  /nippo-add: 1回" <<<"$OUT"

echo ""
echo "結果: $PASS/$TOTAL passed"
[[ $FAIL -eq 0 ]]
