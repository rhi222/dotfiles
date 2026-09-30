#!/bin/bash
# Public entrypoint. Implementation: internal/prwatch/scripts/nightly.sh

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec bash "$SCRIPT_DIR/../../internal/prwatch/scripts/nightly.sh" "$@"
