#!/bin/bash
# secret-scan.sh — repository向け機密情報scanの互換wrapper。
#
# hook・CI・AGENTS.mdなどがこの公開pathを参照するため、内部実装を移しても入口は維持する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/repository/secret-scan.sh" "$@"
