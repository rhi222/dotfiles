#!/bin/bash
# Stable public entrypoint. Implementation: internal/bootstrap/link.sh
set -euo pipefail

DOTFILES_ENTRY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=internal/bootstrap/link.sh
source "$DOTFILES_ENTRY_DIR/internal/bootstrap/link.sh"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
