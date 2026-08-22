#!/bin/bash
# Compatibility Shell API. Implementation: domains/linear/lib/api.sh

_LINEAR_API_COMPAT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$_LINEAR_API_COMPAT_DIR/../../domains/linear/lib/api.sh"
unset _LINEAR_API_COMPAT_DIR
