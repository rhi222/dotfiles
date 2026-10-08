#!/bin/bash
# nippo-finalize の完了チェックは、収集フェーズ（Slack / GitHub / Linear）と
# 分析レポートの痕跡が日報に無ければ、欠けた項目を出して exit 1 を返す。
# 黙ってスキップしたフェーズを見逃さないための検査。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
CHECK="$SCRIPTS_DIR/nippo/finalize-check.sh"

if [[ ! -x "$CHECK" ]]; then
  echo "ERROR: $CHECK が存在しないか実行権限がありません"
  exit 1
fi

# shellcheck source=../../scripts/lib/nippo-paths.sh
source "$SCRIPTS_DIR/lib/nippo-paths.sh"

DATE="2026-03-09"
PASS=0
FAIL=0

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
export NIPPO_DIR="$TEST_DIR"
FIXTURE="$(nippo_daily_file "$DATE")"
mkdir -p "$(nippo_daily_dir "$DATE")"

# $1=期待するexit $2=出力に含まれるべき文字列（空なら出力が空であること） $3=テスト名
expect() {
  local want_exit="$1" want_out="$2" name="$3" out rc=0
  out="$(bash "$CHECK" "$DATE" 2>/dev/null)" || rc=$?
  local out_ok=false
  if [[ -z "$want_out" ]]; then
    [[ -z "$out" ]] && out_ok=true
  elif grep -qF -- "$want_out" <<<"$out"; then
    out_ok=true
  fi
  if [[ "$rc" -eq "$want_exit" && "$out_ok" == true ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (rc=$rc, out=$out)"
  fi
}

COMPLETE='# Daily Growth Log

## 作業ログ（分報・思考メモ）

- 10:54 [Slack/#dev] 発言

## GitHub活動 (someone)

## 今日の作業サマリ（Linear）

---

## Finalize: 日報分析 - 2026-03-09
'

echo "[1] 日報が無い"
rm -f "$FIXTURE"
expect 1 "日報ファイルがありません" "日報が無ければexit 1"

echo "[2] すべて揃っている"
printf '%s' "$COMPLETE" >"$FIXTURE"
expect 0 "" "揃っていればexit 0で出力なし"

echo "[3] Slackの痕跡が無い"
printf '%s' "${COMPLETE/- 10:54 \[Slack\/#dev\] 発言/}" >"$FIXTURE"
expect 1 "Slack" "Slack行もskip印も無ければexit 1"

echo "[4] Slackはskip印でもよい"
printf '%s' "${COMPLETE/- 10:54 \[Slack\/#dev\] 発言/<!-- slack: skipped (MCP未接続) -->}" >"$FIXTURE"
expect 0 "" "slack: の印があればexit 0"

echo "[5] GitHub活動が無い"
printf '%s' "${COMPLETE/"## GitHub活動 (someone)"/}" >"$FIXTURE"
expect 1 "GitHub" "GitHub活動の見出しもskip印も無ければexit 1"

echo "[6] GitHubはskip印でもよい"
printf '%s' "${COMPLETE/"## GitHub活動 (someone)"/<!-- github: skipped (gh未認証) -->}" >"$FIXTURE"
expect 0 "" "github: の印があればexit 0"

echo "[7] Linear作業サマリが無い"
printf '%s' "${COMPLETE/"## 今日の作業サマリ（Linear）"/}" >"$FIXTURE"
expect 1 "Linear" "Linearの見出しもskip印も無ければexit 1"

echo "[8] Linearはskip印でもよい"
printf '%s' "${COMPLETE/"## 今日の作業サマリ（Linear）"/<!-- linear: skipped (API不可) -->}" >"$FIXTURE"
expect 0 "" "linear: の印があればexit 0"

echo "[9] 分析レポートが無い"
printf '%s' "${COMPLETE/"## Finalize: 日報分析 - 2026-03-09"/}" >"$FIXTURE"
expect 1 "Finalize" "Finalize見出しが無ければexit 1"

echo "[10] 欠けた項目はすべて並べる"
printf '# Daily Growth Log\n' >"$FIXTURE"
out="$(bash "$CHECK" "$DATE" 2>/dev/null || true)"
if [[ "$(grep -c '^- ' <<<"$out")" -eq 4 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: 4項目すべてを出す"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: 4項目すべてを出す (out=$out)"
fi

echo ""
echo "TOTAL: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
