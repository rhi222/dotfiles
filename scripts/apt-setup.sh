#!/bin/bash
set -euo pipefail
DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES_FILE="$DOTFILES_DIR/apt-packages.txt"

if [ ! -f "$PACKAGES_FILE" ]; then
  echo "apt-packages.txt not found" >&2
  exit 1
fi

sudo apt update
xargs -a "$PACKAGES_FILE" sudo apt install -y
