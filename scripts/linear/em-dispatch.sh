#!/bin/bash
# Compatibility entrypoint. Implementation: internal/linear/scripts/em-dispatch.sh

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
IMPL="$SCRIPT_DIR/../../internal/linear/scripts/em-dispatch.sh"
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  exec bash "$IMPL" "$@"
fi
# shellcheck source=../../internal/linear/scripts/em-dispatch.sh
source "$IMPL"
