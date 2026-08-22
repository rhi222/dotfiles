#!/bin/bash
# Compatibility Shell API. Implementation: domains/nippo/lib/paths.sh

_NIPPO_PATHS_COMPAT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$_NIPPO_PATHS_COMPAT_DIR/../../domains/nippo/lib/paths.sh"
unset _NIPPO_PATHS_COMPAT_DIR
