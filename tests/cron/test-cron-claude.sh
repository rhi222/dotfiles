#!/bin/bash
# cron-claude はclaudeの引数と終了コードを透過し、ハングを上限で打ち切る。
# enable fileと平日条件を満たさない実行は、副作用なしで正常終了する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
LIB="$SCRIPTS_DIR/lib/cron-claude.sh"

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

refute_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if grep -q -- "$needle" <<<"$haystack"; then
    echo "NG: $desc"
    fail=$((fail + 1))
  else
    echo "ok: $desc"
    pass=$((pass + 1))
  fi
}

if [[ ! -f "$LIB" ]]; then
  echo "ERROR: $LIB が存在しません"
  exit 1
fi

# shellcheck source=/dev/null  # 検査対象は実行時に決まる相対パス
source "$LIB"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 正常終了する claude
cat >"$tmp/claude-ok" <<'EOF'
#!/bin/bash
echo "args: $*"
exit 0
EOF
# ハングする claude
cat >"$tmp/claude-hang" <<'EOF'
#!/bin/bash
sleep 60
EOF
# 異常終了する claude
cat >"$tmp/claude-ng" <<'EOF'
#!/bin/bash
exit 3
EOF
chmod +x "$tmp/claude-ok" "$tmp/claude-hang" "$tmp/claude-ng"

# --- 正常系 ---
out=$(cron_run_claude "日報仕上げ" 10 "$tmp/claude-ok" -p "プロンプト" 2>&1)
rc=$?
check "正常終了なら0を返す" test "$rc" -eq 0
check "引数はそのまま claude に渡る" grep -q -- "-p プロンプト" <<<"$out"
refute_contains "正常時は失敗メッセージを出さない" "失敗" "$out"

# --- タイムアウト ---
start=$(date +%s)
out=$(cron_run_claude "日報仕上げ" 2 "$tmp/claude-hang" 2>&1)
rc=$?
elapsed=$(($(date +%s) - start))
check "タイムアウトは124を返す" test "$rc" -eq 124
check "実際に打ち切られる" test "$elapsed" -lt 30
check "タイムアウトと分かるメッセージを出す" grep -q "タイムアウト" <<<"$out"
check "何がタイムアウトしたか分かる" grep -q "日報仕上げ" <<<"$out"
check "制限秒をメッセージに含める" grep -q "2" <<<"$out"

# --- 異常終了 ---
out=$(cron_run_claude "週次レポート" 10 "$tmp/claude-ng" 2>&1)
rc=$?
check "claudeの終了コードをそのまま返す" test "$rc" -eq 3
check "終了コードをメッセージに含める" grep -q "3" <<<"$out"
check "タイムアウトとは区別する" grep -q "失敗" <<<"$out"

# --- 診断メッセージは stderr へ ---
# cron のログでは stdout と混ざるが、対話実行で成果物だけを拾えるようにする
outonly=$(cron_run_claude "週次レポート" 10 "$tmp/claude-ng" 2>/dev/null)
check "診断メッセージは stdout に出さない" test -z "$outonly"

# --- cron_require_flag ---
# exit を伴うのでサブシェルで隔離し、終了コードと出力を観察する
touch "$tmp/flag-present"

out=$( (
  cron_require_flag "$tmp/flag-present"
  echo "続行"
) 2>&1)
check "フラグがあれば続行する（exit しない）" grep -q "続行" <<<"$out"

out=$( (
  cron_require_flag "$tmp/flag-absent"
  echo "続行"
) 2>&1)
rc=$?
check "フラグが無ければ exit 0 する" test "$rc" -eq 0
refute_contains "フラグが無ければ後続を実行しない" "続行" "$out"
refute_contains "フラグが無ければ何も出さない" "." "$out"

# --- cron_weekday_only ---
# date をスタブして曜日を固定する（PATH 先頭に置いて実 date を隠す）
stubdate() {
  local dow="$1"
  cat >"$tmp/date" <<EOF
#!/bin/bash
if [[ "\$1" == "+%u" ]]; then echo "$dow"; else command date "\$@"; fi
EOF
  chmod +x "$tmp/date"
}

# 平日（月=1）は force に関わらず続行する
stubdate 1
out=$( (
  PATH="$tmp:$PATH" cron_weekday_only 0
  echo "続行"
) 2>&1)
check "平日は続行する" grep -q "続行" <<<"$out"

# 土曜（=6）は force でなければ exit 0 する
stubdate 6
out=$( (
  PATH="$tmp:$PATH" cron_weekday_only 0
  echo "続行"
) 2>&1)
rc=$?
check "土曜は exit 0 する" test "$rc" -eq 0
refute_contains "土曜は後続を実行しない" "続行" "$out"

# 日曜（=7）も同様に exit 0 する
stubdate 7
out=$( (
  PATH="$tmp:$PATH" cron_weekday_only 0
  echo "続行"
) 2>&1)
refute_contains "日曜も後続を実行しない" "続行" "$out"

# 土日でも force=1 なら続行する（テスト・手動実行の抜け道）
stubdate 6
out=$( (
  PATH="$tmp:$PATH" cron_weekday_only 1
  echo "続行"
) 2>&1)
check "force=1 なら土日でも続行する" grep -q "続行" <<<"$out"

# force 未指定（空引数）は既定 0 扱いで、土日はガードする
stubdate 7
out=$( (
  PATH="$tmp:$PATH" cron_weekday_only
  echo "続行"
) 2>&1)
refute_contains "force 未指定なら土日はガードする" "続行" "$out"

rm -f "$tmp/date"

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
