#!/bin/bash
set -euo pipefail

# mise-managed tools (gh, nvim, cargo, ...) must resolve via shims, not via
# the version-locked PATH inherited from a long-running parent shell. After
# `mise upgrade` bumps a tool, the old `installs/<tool>/<ver>/...` path
# becomes stale; for `gh` that means falling through to /usr/bin/gh 2.74.0,
# which lacks the `skill` subcommand and breaks `gh skill update`.
export PATH="$HOME/.local/share/mise/shims:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$HOME/.local/state/daily-update"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
mkdir -p "$LOG_DIR"
# 日次ログは溜まり続けるので、30日より古いものを起動時に掃除する
find "$LOG_DIR" -name '*.log' -mtime +30 -delete 2>/dev/null || true

# shellcheck source=lib/pkg-update.sh
source "$SCRIPT_DIR/lib/pkg-update.sh"

failures=()

run_step() {
  local name="$1"
  shift
  echo "=== $name ===" | tee -a "$LOG_FILE"
  if "$@" 2>&1 | tee -a "$LOG_FILE"; then
    echo "=== $name: OK ===" | tee -a "$LOG_FILE"
  else
    echo "=== $name: FAILED ===" | tee -a "$LOG_FILE"
    failures+=("$name")
  fi
  echo "" | tee -a "$LOG_FILE"
}

# Only update skills managed via `gh skill install` (remote lines in
# claude-skills.txt). Local-cloned or system skills lack GitHub metadata
# and would trigger noisy "Reinstall to enable updates" warnings.
gh_skill_update() {
  local names
  mapfile -t names < <(awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ || /^[[:space:]]*local:/ { next }
    { sub(/[[:space:]]#.*$/, ""); split($2, a, "@"); n = a[1]; sub(/.*\//, "", n); if (n != "") print n }
  ' "$SCRIPT_DIR/claude-skills.txt")

  if [ "${#names[@]}" -eq 0 ]; then
    echo "No remote-managed skills to update."
    return 0
  fi

  gh skill update --all "${names[@]}" </dev/null
}

# 失敗があればWindowsトースト通知を出す。WSL2以外（powershell.exeが無い環境）
# ではスキップ。通知自体の失敗で全体を落とさない。
notify_failures() {
  command -v powershell.exe >/dev/null 2>&1 || return 0
  # shellcheck source=lib/notify-windows-toast.sh
  source "$SCRIPT_DIR/lib/notify-windows-toast.sh"
  send_windows_toast "daily-update 失敗" "FAILED: ${failures[*]}" || true
}

main() {
  run_step "apt update" sudo apt-get update -qq
  run_step "apt upgrade" sudo apt-get upgrade -y -qq
  run_step "cargo install-update" cargo install-update -a
  run_step "mise self-update" mise self-update -y
  run_step "mise upgrade" mise upgrade
  # upgrade で最新でなくなった版を同一実行内で掃除する（tracked 設定から
  # 参照されなくなったツール版を実削除。確認プロンプトなし）
  run_step "mise prune" mise prune
  run_step "npm global update" npm_global_update
  run_step "pip global update" pip_global_update
  run_step "nvim Lazy update" timeout 300 nvim --headless -c "luafile $SCRIPT_DIR/nvim-lazy-update.lua" +qa
  run_step "nvim Mason update" timeout 300 nvim --headless -c 'autocmd User MasonUpdateAllComplete quitall' -c 'MasonUpdateAll'
  # New skills are added via `scripts/skill-add.sh`; bootstrap uses
  # `setup-claude-skills.sh`. Daily only runs the update step.
  run_step "gh skill update" gh_skill_update

  echo "========================================" | tee -a "$LOG_FILE"
  if [ ${#failures[@]} -gt 0 ]; then
    echo "FAILED: ${failures[*]}" | tee -a "$LOG_FILE"
    notify_failures
    exit 1
  else
    echo "All updates completed successfully." | tee -a "$LOG_FILE"
  fi
}

# Only run the update pipeline when executed directly; sourcing (e.g. from
# test-daily-update.sh) loads the functions without triggering any updates.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
