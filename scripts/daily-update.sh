#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$HOME/.local/state/daily-update"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
mkdir -p "$LOG_DIR"

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

check_nvim_version() {
  local current latest
  current=$(nvim --version | head -1 | awk '{print $2}')
  latest=$(gh release list --repo neovim/neovim --exclude-pre-releases --limit 1 \
    --json tagName,isLatest -q '.[] | select(.isLatest) | .tagName')
  echo "current: $current"
  echo "latest (stable): $latest"
  if [ -n "$latest" ] && [ "$current" != "$latest" ]; then
    echo ">>> NEW VERSION AVAILABLE: $current -> $latest <<<"
  fi
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

# run_step "apt update" sudo apt-get update -qq
run_step "apt upgrade" sudo apt-get upgrade -y -qq
run_step "cargo install-update" cargo install-update -a
run_step "mise self-update" mise self-update -y
run_step "mise upgrade" mise upgrade
run_step "nvim version check" check_nvim_version
run_step "nvim Lazy update" timeout 300 nvim --headless "+Lazy! update" +qa
run_step "nvim Mason update" timeout 300 nvim --headless -c 'autocmd User MasonUpdateAllComplete quitall' -c 'MasonUpdateAll'
# New skills are added via `scripts/skill-add.sh`; bootstrap uses
# `setup-claude-skills.sh`. Daily only runs the update step.
run_step "gh skill update" gh_skill_update

echo "========================================" | tee -a "$LOG_FILE"
if [ ${#failures[@]} -gt 0 ]; then
  echo "FAILED: ${failures[*]}" | tee -a "$LOG_FILE"
  exit 1
else
  echo "All updates completed successfully." | tee -a "$LOG_FILE"
fi
