#!/bin/bash
# Deploy the fish plugins declared in .config/fish/fish_plugins via fisher.
#
# Usage:  bash scripts/setup/fish-plugins.sh [--dry-run]
#
# fish_plugins line format:
#   <owner>/<repo>[@<version>]     # `#`-prefixed and inline comments ignored
#
# Why this exists: `fish_plugins` used to be untracked, so plugin sets drifted
# per machine and nothing updated them (`daily-update.sh` covers apt/cargo/mise/
# npm/pip/nvim/gh/yazi but had no fisher step). The Ctrl+R timestamp fix kept
# reverting because the terminals disagreed about which plugin owned the key.
#
# `fisher update` with no arguments is a full reconcile against fish_plugins:
# it installs what is missing, updates what is present, and REMOVES anything
# installed but undeclared. That is the declarative contract we want, but the
# removal half is destructive, so undeclared plugins are named before running.
#
# Idempotent: `fisher update` runs only when the declared set and the installed
# set differ, so re-running on a healthy machine costs no network round-trip.
#
# Env flags:
#   STRICT=1              : fail hard on missing prereqs (bootstrap)
#   FISH_PLUGINS_FILE=    : override the declaration file path (tests)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PLUGINS_FILE="${FISH_PLUGINS_FILE:-$SCRIPT_DIR/../../.config/fish/fish_plugins}"
STRICT="${STRICT:-0}"
DRY_RUN=0

# fisher itself is fetched from upstream when absent. Kept as a constant so the
# bootstrap command reads the same here and in docs/bootstrap.md.
FISHER_URL="https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      echo "Usage: setup-fish-plugins.sh [--dry-run]"
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

prereq_fail() {
  local msg="$1"
  if [ "$STRICT" = "1" ]; then
    echo "Error: $msg" >&2
    exit 1
  else
    echo "Warning: $msg, skipping" >&2
    exit 0
  fi
}

if [ ! -f "$PLUGINS_FILE" ]; then
  echo "Error: $PLUGINS_FILE not found" >&2
  exit 1
fi

# Parse declarations. fisher lowercases plugin names before storing them in
# $_fisher_plugins, so compare lowercased on both sides.
declared=()
line_no=0
while IFS= read -r raw_line || [ -n "${raw_line:-}" ]; do
  line_no=$((line_no + 1))

  line="${raw_line#"${raw_line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  line="${line%%[[:space:]]\#*}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue

  if [[ "$line" =~ [[:space:]] ]]; then
    echo "Error: malformed line $line_no: $line" >&2
    exit 1
  fi

  declared+=("${line,,}")
done <"$PLUGINS_FILE"

if [ "${#declared[@]}" -eq 0 ]; then
  echo "Nothing declared in $PLUGINS_FILE."
  exit 0
fi

if ! command -v fish >/dev/null 2>&1; then
  prereq_fail "fish not found"
fi

# fisher is a fish function, not a binary, so `command -v` cannot see it.
if fish -c 'functions -q fisher' >/dev/null 2>&1; then
  has_fisher=1
else
  has_fisher=0
fi

if [ "$has_fisher" -eq 0 ]; then
  echo "fisher is not installed."
  if [ "$DRY_RUN" = "1" ]; then
    echo "  -> [dry-run] bootstrap fisher, then fisher update"
    exit 0
  fi
  echo "  -> bootstrapping fisher"
  if ! fish -c "curl -sL $FISHER_URL | source && fisher install jorgebucaran/fisher" </dev/null; then
    echo "Error: failed to bootstrap fisher" >&2
    exit 1
  fi
fi

# Installed set, as fisher reports it.
installed=()
while IFS= read -r plugin; do
  plugin="${plugin%"${plugin##*[![:space:]]}"}"
  [ -n "$plugin" ] && installed+=("${plugin,,}")
done < <(fish -c 'fisher list' 2>/dev/null)

contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

missing=()
for plugin in "${declared[@]}"; do
  contains "$plugin" ${installed+"${installed[@]}"} || missing+=("$plugin")
done

undeclared=()
for plugin in ${installed+"${installed[@]}"}; do
  contains "$plugin" "${declared[@]}" || undeclared+=("$plugin")
done

if [ "${#missing[@]}" -eq 0 ] && [ "${#undeclared[@]}" -eq 0 ]; then
  echo "All ${#declared[@]} fish plugin(s) are in sync."
  exit 0
fi

[ "${#missing[@]}" -gt 0 ] && echo "Missing fish plugin(s): ${missing[*]}"

# `fisher update` deletes these. Name them first — silently removing a plugin
# somebody installed by hand on this machine is the one irreversible thing here.
if [ "${#undeclared[@]}" -gt 0 ]; then
  echo "Installed but not declared (fisher update will REMOVE): ${undeclared[*]}"
  echo "  keep one by adding it to $PLUGINS_FILE"
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "  -> [dry-run] fisher update"
  exit 0
fi

echo "  -> fisher update"
if ! fish -c 'fisher update' </dev/null; then
  echo "Error: fisher update failed" >&2
  exit 1
fi

# Trust the filesystem, not the exit code: a green `fisher update` that
# installed nothing leaves the shell silently degraded (no prompt, no Ctrl+R).
after=()
while IFS= read -r plugin; do
  plugin="${plugin%"${plugin##*[![:space:]]}"}"
  [ -n "$plugin" ] && after+=("${plugin,,}")
done < <(fish -c 'fisher list' 2>/dev/null)

still_missing=()
for plugin in "${declared[@]}"; do
  contains "$plugin" ${after+"${after[@]}"} || still_missing+=("$plugin")
done

if [ "${#still_missing[@]}" -gt 0 ]; then
  echo "Error: still missing after fisher update: ${still_missing[*]}" >&2
  exit 1
fi

echo "Done."
