#!/bin/bash
# Compatibility entrypoint. Implementation: domains/linear/scripts/interview-prep.sh

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
IMPL="$SCRIPT_DIR/../domains/linear/scripts/interview-prep.sh"
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  exec bash "$IMPL" "$@"
fi
# shellcheck source=../domains/linear/scripts/interview-prep.sh
source "$IMPL"
