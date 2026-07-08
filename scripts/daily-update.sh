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

# Decide which managed npm globals actually need (re)installing. A package is
# a target when it is either flagged by `npm outdated` (a newer version exists)
# or not currently installed at all (newly added to the list — `npm outdated`
# never reports missing packages). Pure function: all inputs are arguments, so
# it is unit-testable without touching the network.
#
# Args: <outdated_json> <installed_names> <name...>
#   outdated_json  : `npm outdated -g --json` output (empty string ok)
#   installed_names: newline-separated names of currently-installed globals
# Prints one "<name>@latest" per target, newline-separated.
npm_select_targets() {
  local outdated_json="$1"
  local installed="$2"
  shift 2
  [ -n "$outdated_json" ] || outdated_json='{}'

  local n
  for n in "$@"; do
    if jq -e --arg n "$n" 'has($n)' <<<"$outdated_json" >/dev/null 2>&1; then
      printf '%s@latest\n' "$n"
    elif ! grep -qxF -- "$n" <<<"$installed"; then
      printf '%s@latest\n' "$n"
    fi
  done
}

# Update global npm packages listed in .default-npm-packages to @latest.
# `mise upgrade` only bumps language runtimes; npm globals installed via
# mise's default-npm-packages hook are not touched after first install.
#
# `npm install -g pkg@latest` re-resolves and reinstalls the full dependency
# tree unconditionally — slow even when nothing changed. Instead, a fast,
# metadata-only `npm outdated -g` check (~1s, no tree resolution/download)
# narrows the install to only the packages that actually moved.
npm_global_update() {
  local file="$HOME/.config/mise/.default-npm-packages"
  if [ ! -f "$file" ]; then
    echo "Skip: $file not found"
    return 0
  fi

  local names
  mapfile -t names < <(awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    { sub(/[[:space:]]#.*$/, ""); gsub(/[[:space:]]/, ""); if ($0 != "") print }
  ' "$file")

  if [ "${#names[@]}" -eq 0 ]; then
    echo "No packages to update."
    return 0
  fi

  # `npm outdated` exits 1 when anything is outdated, so guard with `|| true`.
  local outdated_json installed
  outdated_json=$(npm outdated -g --json 2>/dev/null || true)
  installed=$(npm list -g --depth=0 --json 2>/dev/null \
    | jq -r '.dependencies // {} | keys[]')

  local targets
  mapfile -t targets < <(npm_select_targets "$outdated_json" "$installed" "${names[@]}")

  if [ "${#targets[@]}" -eq 0 ]; then
    echo "No package changes."
    return 0
  fi

  local before_file after_file rc
  before_file=$(mktemp)
  after_file=$(mktemp)

  list_npm_globals >"$before_file"
  npm install -g --no-audit --no-fund "${targets[@]}" >/dev/null
  rc=$?
  list_npm_globals >"$after_file"

  report_pkg_diff "$before_file" "$after_file"
  rm -f "$before_file" "$after_file"
  return $rc
}

# PEP 503 name normalizer (stream filter): lowercase and collapse runs of
# -, _, . to a single -, so e.g. typing_extensions and typing-extensions match.
_pip_normalize() {
  tr '[:upper:]' '[:lower:]' | sed -E 's/[-_.]+/-/g'
}

# Decide which managed pip packages need (re)installing. A spec is a target
# when its base name (extras like [all] stripped) is flagged by
# `pip list --outdated` or is not currently installed. Names are compared
# PEP 503-normalized. The original spec (extras kept) is what gets printed so
# `pip install -U python-lsp-server[all]` keeps its extras. Pure/unit-testable.
#
# Args: <outdated_json> <installed_names> <spec...>
#   outdated_json  : `pip list --outdated --format=json` output (empty ok)
#   installed_names: newline-separated names of currently-installed packages
# Prints the original specs that need installing, newline-separated.
pip_select_targets() {
  local outdated_json="$1"
  local installed="$2"
  shift 2
  [ -n "$outdated_json" ] || outdated_json='[]'

  local outdated_norm installed_norm
  outdated_norm=$(jq -r '.[].name' <<<"$outdated_json" 2>/dev/null | _pip_normalize)
  installed_norm=$(_pip_normalize <<<"$installed")

  local spec base base_norm
  for spec in "$@"; do
    base=$(printf '%s' "$spec" | sed 's/\[.*//')   # strip extras: foo[all] -> foo
    base_norm=$(_pip_normalize <<<"$base")
    if grep -qxF -- "$base_norm" <<<"$outdated_norm"; then
      printf '%s\n' "$spec"
    elif ! grep -qxF -- "$base_norm" <<<"$installed_norm"; then
      printf '%s\n' "$spec"
    fi
  done
}

# Same idea as npm for pip globals listed in .default-python-packages.
# A fast, metadata-only `pip list --outdated` check narrows the reinstall to
# packages that moved or are missing. pip's default only-if-needed upgrade
# strategy means an already-latest top-level package is a no-op anyway, so
# skipping it is behavior-preserving.
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

  local outdated_json installed
  outdated_json=$(pip list --outdated --format=json 2>/dev/null || true)
  installed=$(pip list --format=json 2>/dev/null | jq -r '.[].name')

  local targets
  mapfile -t targets < <(pip_select_targets "$outdated_json" "$installed" "${packages[@]}")

  if [ "${#targets[@]}" -eq 0 ]; then
    echo "No package changes."
    return 0
  fi

  local before_file after_file rc
  before_file=$(mktemp)
  after_file=$(mktemp)

  list_pip_globals >"$before_file"
  pip install -U "${targets[@]}" >/dev/null
  rc=$?
  list_pip_globals >"$after_file"

  report_pkg_diff "$before_file" "$after_file"
  rm -f "$before_file" "$after_file"
  return $rc
}

main() {
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
}

# Only run the update pipeline when executed directly; sourcing (e.g. from
# test-daily-update.sh) loads the functions without triggering any updates.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
