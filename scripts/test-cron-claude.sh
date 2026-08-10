#!/bin/bash
# lib/cron-claude.sh のテスト
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/lib/cron-claude.sh"

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

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
