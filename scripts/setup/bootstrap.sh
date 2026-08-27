#!/bin/bash
# New-machine initialization. Repeatable linking remains in ../../dotfilesLink.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../internal/bootstrap/setup.sh
source "$SCRIPT_DIR/../../internal/bootstrap/setup.sh"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  bootstrap_main "$@"
fi
