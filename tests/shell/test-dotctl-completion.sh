#!/bin/bash
# dotctl のトップレベルサブコマンドが説明付きで補完されることを固定する。
# サブコマンド位置では通常のファイル候補を混ぜず、選択後は同じ候補を出さない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FISH_CONFIG="$REPO_ROOT/.config/fish/config.fish"
COMPLETION_DIR="$REPO_ROOT/.config/fish/my/completions"
COMPLETION_FILE="$COMPLETION_DIR/dotctl.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi

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

check "config.fish が個人補完を優先する" \
  grep -qF 'set -g fish_complete_path ~/.config/fish/my/completions $fish_complete_path' "$FISH_CONFIG"
check "dotctl の補完定義がある" test -f "$COMPLETION_FILE"

completions=$(fish --no-config -c \
  "set -g fish_complete_path '$COMPLETION_DIR' \$fish_complete_path; complete -C 'dotctl '")
candidates=$(printf '%s\n' "$completions" | cut -f1 | sort)
expected=$(printf '%s\n' \
  agent-usage \
  docker \
  doctor \
  fisher-update \
  help \
  private-bundle \
  rebuild \
  settings \
  skill \
  version \
  worktree \
  wsl)

check "全トップレベルサブコマンドを補完する" test "$candidates" = "$expected"
check "候補に説明を付ける" test "$(printf '%s\n' "$completions" | grep -c $'\t')" -eq 12

nested=$(fish --no-config -c \
  "set -g fish_complete_path '$COMPLETION_DIR' \$fish_complete_path; complete -C 'dotctl worktree '")
check "第2階層のサブコマンドも補完する" \
  test "$(printf '%s\n' "$nested" | cut -f1 | sort)" = $'cleanup\ninit'

terminal=$(fish --no-config -c \
  "set -g fish_complete_path '$COMPLETION_DIR' \$fish_complete_path; complete -C 'dotctl worktree cleanup '")
terminal_candidates=$(printf '%s\n' "$terminal" | cut -f1)
check "選択後はトップレベル候補を再提示しない" \
  test "$(printf '%s\n' "$terminal_candidates" | grep -cFx worktree)" -eq 0

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
