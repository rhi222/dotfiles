#!/bin/bash
# Compatibility entrypoint. Implementation: domains/linear/scripts/bootstrap.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec bash "$SCRIPT_DIR/../domains/linear/scripts/bootstrap.sh" "$@"
