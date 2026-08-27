#!/bin/bash
# Deploy the yazi plugins/flavors declared in yazi's package.toml.
#
# Usage:  bash scripts/setup/yazi-plugins.sh [--dry-run]
#
# `.config/yazi/plugins/` is gitignored (upstream code is not vendored), so a
# fresh clone has the declarations but none of the bodies. yazi's init.lua does
# `require("git")`, which makes this fatal rather than degraded: yazi exits 1
# with "Failed to load plugin from .../git.yazi/main.lua" and never starts.
# New-machine bootstrap runs this after linking ~/.config/yazi.
#
# Idempotent: `ya pkg install` runs only when a declared package has no body,
# so re-running on a healthy machine costs no network round-trip.
#
# Env flags:
#   STRICT=1            : fail hard on missing prereqs (bootstrap)
#   YAZI_CONFIG_HOME=   : yazi config dir (same variable `ya` itself honors)
#   XDG_CONFIG_HOME=    : fallback base for the config dir
#
# Note: this script deliberately uses bash builtins only (no grep/sed/awk),
# so the `ya not found` path can be exercised with an empty PATH.
set -uo pipefail

STRICT="${STRICT:-0}"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      echo "Usage: setup-yazi-plugins.sh [--dry-run]"
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

# Resolve the config dir the same way `ya` does, so both look at one package.toml.
if [ -n "${YAZI_CONFIG_HOME:-}" ]; then
  CONFIG_DIR="$YAZI_CONFIG_HOME"
elif [ -n "${XDG_CONFIG_HOME:-}" ]; then
  CONFIG_DIR="$XDG_CONFIG_HOME/yazi"
else
  CONFIG_DIR="$HOME/.config/yazi"
fi
PACKAGE_FILE="$CONFIG_DIR/package.toml"

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

# A package's body lives in plugins/<name>.yazi or flavors/<name>.yazi.
has_body() {
  [ -d "$CONFIG_DIR/plugins/$1.yazi" ] || [ -d "$CONFIG_DIR/flavors/$1.yazi" ]
}

if [ ! -f "$PACKAGE_FILE" ]; then
  echo "Skipped: no package.toml in $CONFIG_DIR"
  exit 0
fi

# `use = "owner/repo:name"` -> name, `use = "owner/repo.yazi"` -> repo sans suffix.
declared=0
missing=()

while IFS= read -r raw_line || [ -n "${raw_line:-}" ]; do
  line="${raw_line#"${raw_line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"

  case "$line" in
    use=* | use[[:space:]]*) ;;
    *) continue ;;
  esac

  rest="${line#*\"}"
  [ "$rest" = "$line" ] && continue
  spec="${rest%%\"*}"
  [ -z "$spec" ] && continue

  if [[ "$spec" == *:* ]]; then
    name="${spec##*:}"
  else
    name="${spec##*/}"
    name="${name%.yazi}"
  fi
  [ -z "$name" ] && continue

  declared=$((declared + 1))
  has_body "$name" || missing+=("$name")
done <"$PACKAGE_FILE"

if [ "$declared" -eq 0 ]; then
  echo "Nothing declared in $PACKAGE_FILE."
  exit 0
fi

if [ "${#missing[@]}" -eq 0 ]; then
  echo "All $declared yazi package(s) are up to date."
  exit 0
fi

echo "Missing yazi package body: ${missing[*]}"

if [ "$DRY_RUN" = "1" ]; then
  echo "  -> [dry-run] ya pkg install"
  exit 0
fi

if ! command -v ya >/dev/null 2>&1; then
  prereq_fail "ya not found (comes with yazi; install it via mise)"
fi

echo "  -> ya pkg install"
ya pkg install </dev/null
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "Error: ya pkg install exited $rc" >&2
  exit 1
fi

# Trust the filesystem, not the exit code: a green `ya pkg install` that
# deployed nothing is exactly the state that breaks yazi at startup.
still_missing=()
for name in "${missing[@]}"; do
  has_body "$name" || still_missing+=("$name")
done

if [ "${#still_missing[@]}" -gt 0 ]; then
  echo "Error: still missing after install: ${still_missing[*]}" >&2
  echo "       yazi will fail to start while init.lua requires them" >&2
  exit 1
fi

echo "Done."
