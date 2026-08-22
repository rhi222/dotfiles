#!/bin/bash
# Stable public entrypoint for repeatable link reconciliation.
set -euo pipefail

DOTFILES_ENTRY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/link/reconcile.sh
source "$DOTFILES_ENTRY_DIR/internal/link/reconcile.sh"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  link_main "$@"
fi
