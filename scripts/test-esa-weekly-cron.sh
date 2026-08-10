#!/bin/bash
# esa-weekly-cron.sh のテスト
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/esa-weekly-cron.sh"
pass=0
fail=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "NG: $desc"
    fail=$((fail + 1))
  fi
}

# 1. フラグファイルなし → 何もせず正常終了
tmp_home1=$(mktemp -d)
out1=$(HOME="$tmp_home1" bash "$SCRIPT" 2>&1)
check "フラグなしで静かにスキップする" test -z "$out1"

# 2. フラグあり + DRY_RUN → 実行予定内容を表示して終了
tmp_home2=$(mktemp -d)
mkdir -p "$tmp_home2/.config"
touch "$tmp_home2/.config/esa-weekly-enabled"
out2=$(HOME="$tmp_home2" ESA_WEEKLY_DRY_RUN=1 bash "$SCRIPT" 2>&1)
check "DRY_RUNで実行内容を表示する" grep -q "DRY_RUN" <<<"$out2"
check "DRY_RUNでesa-weekly-reportを呼ぶ予定が表示される" grep -q "esa-weekly-report" <<<"$out2"

# 3. DRY_RUNでclaude本体が呼ばれていないこと
out3=$(HOME="$tmp_home2" ESA_WEEKLY_DRY_RUN=1 CLAUDE_BIN=/nonexistent/claude bash "$SCRIPT" 2>&1)
check "DRY_RUNではclaudeを実行しない" grep -q "DRY_RUN" <<<"$out3"

# 4. ハングしても打ち切られること。
# cron から無人で走るので、止まらないと次の週次実行まで残り続ける
hang=$(mktemp -d)
printf '#!/bin/bash\nsleep 60\n' >"$hang/claude"
chmod +x "$hang/claude"

start=$(date +%s)
out4=$(HOME="$tmp_home2" CLAUDE_BIN="$hang/claude" ESA_WEEKLY_TIMEOUT=2 bash "$SCRIPT" 2>&1)
rc4=$?
elapsed=$(($(date +%s) - start))
check "ハングしたらタイムアウトで打ち切る" test "$elapsed" -lt 30
check "タイムアウトは非0で終わる" test "$rc4" -ne 0
check "タイムアウトしたと分かる出力を出す" grep -q "タイムアウト" <<<"$out4"

rm -rf "$tmp_home1" "$tmp_home2" "$hang"

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
