#!/bin/bash
# Install all gh CLI extensions declared in gh-extensions.txt.
#
# Usage:  bash scripts/setup/gh-extensions.sh [--dry-run]
#
# gh-extensions.txt line format:
#   <owner>/<repo>[@<version>]     # `#`-prefixed and inline comments ignored
#
# Already-installed extensions are skipped (version is not reconciled;
# `daily-update.sh` runs `gh extension upgrade --all` for that).
#
# Env flags:
#   STRICT=1              : fail hard on missing prereqs (bootstrap)
#   GH_EXTENSIONS_FILE=   : override the declaration file path (tests)
#
# Note: this script deliberately uses bash builtins only (no grep/sed/awk),
# so the `gh not found` path can be exercised with an empty PATH.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
EXT_FILE="${GH_EXTENSIONS_FILE:-$SCRIPT_DIR/gh-extensions.txt}"
STRICT="${STRICT:-0}"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      echo "Usage: setup-gh-extensions.sh [--dry-run]"
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

if [ ! -f "$EXT_FILE" ]; then
  echo "Error: $EXT_FILE not found" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  prereq_fail "gh not found"
fi

if ! gh auth status >/dev/null 2>&1; then
  prereq_fail "gh not authenticated (run 'gh auth login')"
fi

# Collect installed extensions as a lowercased "owner/repo" set.
declare -A installed=()
while IFS=$'\t' read -r _name repo _rest; do
  repo="${repo#"${repo%%[![:space:]]*}"}"
  repo="${repo%"${repo##*[![:space:]]}"}"
  [ -n "$repo" ] && installed["${repo,,}"]=1
done < <(gh extension list 2>/dev/null || true)

echo "Installing gh extensions from $EXT_FILE..."

failures=()
attempted=0
succeeded=0
skipped=0
line_no=0

while IFS= read -r raw_line || [ -n "${raw_line:-}" ]; do
  line_no=$((line_no + 1))

  # Trim surrounding whitespace, drop full-line and inline `#` comments.
  line="${raw_line#"${raw_line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  line="${line%%[[:space:]]\#*}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue

  read -r spec extra <<<"$line"
  version="${spec#*@}"
  repo="${spec%@*}"
  [ "$version" = "$spec" ] && version=""

  if [ -n "${extra:-}" ] || [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "  -> skip (malformed line $line_no): $line"
    failures+=("line $line_no: malformed: $line")
    attempted=$((attempted + 1))
    continue
  fi

  if [ -n "${installed[${repo,,}]:-}" ]; then
    echo "  -> skip (already installed): $repo"
    skipped=$((skipped + 1))
    continue
  fi

  cmd=(gh extension install "$repo")
  [ -n "$version" ] && cmd+=(--pin "$version")

  if [ "$DRY_RUN" = "1" ]; then
    echo "  -> [dry-run] ${cmd[*]}"
    skipped=$((skipped + 1))
    continue
  fi

  echo "  -> ${cmd[*]}"
  attempted=$((attempted + 1))
  if "${cmd[@]}" </dev/null; then
    succeeded=$((succeeded + 1))
  else
    rc=$?
    echo "  -> ERROR: gh extension install exited $rc ($repo)" >&2
    failures+=("line $line_no: $line")
  fi
done <"$EXT_FILE"

echo ""
echo "Finished: $succeeded succeeded, $skipped skipped, $attempted attempted."

if [ "${#failures[@]}" -gt 0 ]; then
  echo "Failed extension installs (${#failures[@]}):" >&2
  for failure in "${failures[@]}"; do
    echo "  - $failure" >&2
  done
  exit 1
fi

echo "Done."
