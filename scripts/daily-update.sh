#!/bin/bash
set -euo pipefail

# mise-managed tools (gh, nvim, cargo, ...) must resolve via shims, not via
# the version-locked PATH inherited from a long-running parent shell. After
# `mise upgrade` bumps a tool, the old `installs/<tool>/<ver>/...` path
# becomes stale; for `gh` that means falling through to /usr/bin/gh 2.74.0,
# which lacks the `skill` subcommand and breaks `gh skill update`.
export PATH="$HOME/.local/share/mise/shims:$PATH"

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

# Tab-separated "name<TAB>version" snapshot of currently installed global
# npm packages, sorted for deterministic diffing.
list_npm_globals() {
  npm list -g --depth=0 --json 2>/dev/null \
    | jq -r '.dependencies // {} | to_entries[] | "\(.key)\t\(.value.version // "?")"' \
    | sort
}

list_pip_globals() {
  pip list --format=json 2>/dev/null \
    | jq -r '.[] | "\(.name | ascii_downcase)\t\(.version)"' \
    | sort
}

# Compare two snapshot files and print a human-friendly summary of upgrades
# and newly-installed packages.
report_pkg_diff() {
  awk -F'\t' '
    NR==FNR { before[$1] = $2; next }
    {
      if (!($1 in before)) {
        added = added sprintf("  %s %s (new)\n", $1, $2); na++
      } else if (before[$1] != $2) {
        upgraded = upgraded sprintf("  %s %s → %s\n", $1, before[$1], $2); nu++
      }
    }
    END {
      if (nu > 0) printf "Upgraded %d package(s):\n%s", nu, upgraded
      if (na > 0) printf "Installed %d new package(s):\n%s", na, added
      if (nu == 0 && na == 0) print "No package changes."
    }
  ' "$1" "$2"
}

# Re-install global npm packages listed in .default-npm-packages at @latest.
# `mise upgrade` only bumps language runtimes; npm globals installed via
# mise's default-npm-packages hook are not touched after first install.
npm_global_update() {
  local file="$HOME/.config/mise/.default-npm-packages"
  if [ ! -f "$file" ]; then
    echo "Skip: $file not found"
    return 0
  fi

  local packages
  mapfile -t packages < <(awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    { sub(/[[:space:]]#.*$/, ""); gsub(/[[:space:]]/, ""); if ($0 != "") print $0 "@latest" }
  ' "$file")

  if [ "${#packages[@]}" -eq 0 ]; then
    echo "No packages to update."
    return 0
  fi

  local before_file after_file rc
  before_file=$(mktemp)
  after_file=$(mktemp)

  list_npm_globals >"$before_file"
  npm install -g "${packages[@]}" >/dev/null
  rc=$?
  list_npm_globals >"$after_file"

  report_pkg_diff "$before_file" "$after_file"
  rm -f "$before_file" "$after_file"
  return $rc
}

# Same idea for pip globals listed in .default-python-packages.
pip_global_update() {
  local file="$HOME/.config/mise/.default-python-packages"
  if [ ! -f "$file" ]; then
    echo "Skip: $file not found"
    return 0
  fi

  local packages
  mapfile -t packages < <(awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    { sub(/[[:space:]]#.*$/, ""); gsub(/[[:space:]]/, ""); if ($0 != "") print }
  ' "$file")

  if [ "${#packages[@]}" -eq 0 ]; then
    echo "No packages to update."
    return 0
  fi

  local before_file after_file rc
  before_file=$(mktemp)
  after_file=$(mktemp)

  list_pip_globals >"$before_file"
  pip install -U "${packages[@]}" >/dev/null
  rc=$?
  list_pip_globals >"$after_file"

  report_pkg_diff "$before_file" "$after_file"
  rm -f "$before_file" "$after_file"
  return $rc
}

run_step "apt update" sudo apt-get update -qq
run_step "apt upgrade" sudo apt-get upgrade -y -qq
run_step "cargo install-update" cargo install-update -a
run_step "mise self-update" mise self-update -y
run_step "mise upgrade" mise upgrade
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
  exit 1
else
  echo "All updates completed successfully." | tee -a "$LOG_FILE"
fi
