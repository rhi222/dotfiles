#!/bin/bash
set -uo pipefail

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

run_step "apt update" sudo apt-get update -qq
run_step "apt upgrade" sudo apt-get upgrade -y -qq
run_step "cargo install-update" cargo install-update -a
run_step "mise self-update" mise self-update -y
run_step "mise upgrade" mise upgrade
run_step "nvim Lazy update" timeout 300 nvim --headless "+Lazy! update" +qa
run_step "nvim Mason update" timeout 300 nvim --headless -c 'autocmd User MasonUpdateAllComplete quitall' -c 'MasonUpdateAll'

echo "========================================" | tee -a "$LOG_FILE"
if [ ${#failures[@]} -gt 0 ]; then
  echo "FAILED: ${failures[*]}" | tee -a "$LOG_FILE"
  exit 1
else
  echo "All updates completed successfully." | tee -a "$LOG_FILE"
fi
