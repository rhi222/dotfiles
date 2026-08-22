#!/bin/bash
# Compatibility entrypoint. Implementation: internal/linear/scripts/bootstrap.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec bash "$SCRIPT_DIR/../internal/linear/scripts/bootstrap.sh" "$@"
