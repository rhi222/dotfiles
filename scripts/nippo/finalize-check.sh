#!/bin/bash
# Compatibility entrypoint. Implementation: internal/nippo/scripts/finalize-check.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec bash "$SCRIPT_DIR/../../internal/nippo/scripts/finalize-check.sh" "$@"
