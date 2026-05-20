#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/apt-packages.txt"

if [ ! -f "$PACKAGES_FILE" ]; then
  echo "apt-packages.txt not found" >&2
  exit 1
fi

sudo apt update
# Strip `#`-prefixed comments and blank lines so future annotations don't
# leak into the package list.
grep -vE '^\s*(#|$)' "$PACKAGES_FILE" | xargs sudo apt install -y
