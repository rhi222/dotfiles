#!/bin/bash
# Compatibility entrypoint. Implementation: internal/followup/scripts/targets.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec bash "$SCRIPT_DIR/../../internal/followup/scripts/targets.sh" "$@"
