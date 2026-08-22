#!/bin/bash
# Compatibility entrypoint. Implementation: internal/linear/scripts/sweep.sh

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
IMPL="$SCRIPT_DIR/../internal/linear/scripts/sweep.sh"
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  exec bash "$IMPL" "$@"
fi
# shellcheck source=../internal/linear/scripts/sweep.sh
source "$IMPL"
