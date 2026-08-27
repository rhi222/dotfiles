#!/bin/bash
# feature別配置より前にbuildされたdotctlが使うbootstrap互換path。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec bash "$SCRIPT_DIR/setup/dotctl.sh" "$@"
