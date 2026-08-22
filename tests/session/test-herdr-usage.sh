#!/bin/bash
# .config/herdr/scripts/{usage,usage-popup}.sh のユニットテスト
#
# tab bar の command エントリとして呼ばれるので、
#   ・dotctl が無い環境では空出力・exit 0 で欄ごと落とすこと
#   ・dotctl があればその1行出力をそのまま返すこと
#   ・出力が1行に収まること
# を検証する。dotctl は HERDR_USAGE_DOTCTL でスタブに差し替える。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET="$REPO_ROOT/.config/herdr/scripts/usage.sh"
POPUP_TARGET="$REPO_ROOT/.config/herdr/scripts/usage-popup.sh"

for target in "$TARGET" "$POPUP_TARGET"; do
  if [[ ! -x "$target" ]]; then
    echo "ERROR: $target が実行可能ファイルとして存在しません"
    exit 1
  fi
done

PASS=0
FAIL=0
TOTAL=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ok() {
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

ng() {
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

echo "test: dotctl が無ければ空出力・exit 0"
out="$(HERDR_USAGE_DOTCTL="$WORK/no-such-dotctl" "$TARGET")"
code=$?
if [[ $code -eq 0 && -z "$out" ]]; then
  ok "空出力 exit 0"
else
  ng "exit=$code out='$out'"
fi

echo "test: dotctl の出力をそのまま返す"
cat >"$WORK/dotctl" <<'STUB'
#!/bin/bash
[ "$1 $2" = "agent-usage line" ] || exit 9
printf 'CC 5h 45%% (2h47m) weekly 50%% fable 29%% (3d11h)'
STUB
chmod +x "$WORK/dotctl"
out="$(HERDR_USAGE_DOTCTL="$WORK/dotctl" "$TARGET")"
code=$?
if [[ $code -eq 0 && "$out" == "CC 5h 45% (2h47m) weekly 50% fable 29% (3d11h)" ]]; then
  ok "出力の中継"
else
  ng "exit=$code out='$out'"
fi

echo "test: 出力が複数行にならない"
if [[ "$out" != *$'\n'* ]]; then
  ok "1行"
else
  ng "改行が含まれる"
fi

echo "test: popup は色付き detail を要求する"
cat >"$WORK/dotctl-popup" <<'STUB'
#!/bin/bash
[ "$*" = "agent-usage detail --color" ] || exit 9
printf '\033[1;36mClaude Code\033[0m\n'
STUB
chmod +x "$WORK/dotctl-popup"
out="$(printf x | HERDR_USAGE_DOTCTL="$WORK/dotctl-popup" "$POPUP_TARGET")"
code=$?
if [[ $code -eq 0 && "$out" == *$'\033[1;36mClaude Code'* && "$out" == *$'\033[2m[press any key]'* ]]; then
  ok "色付き detail と dim の終了案内"
else
  ng "exit=$code out='$out'"
fi

echo
echo "result: $PASS/$TOTAL passed"
[[ $FAIL -eq 0 ]]
