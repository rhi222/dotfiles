#!/bin/bash
# Compatibility entrypoint. Implementation: domains/nippo/scripts/notify-cron.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec bash "$SCRIPT_DIR/../domains/nippo/scripts/notify-cron.sh" "$@"
