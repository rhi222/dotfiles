#!/bin/bash
# sync-claude-settings.sh — dotctl settings sync claude への互換 wrapper。
#
#   bash scripts/sync-claude-settings.sh pull [--dry-run]  # 実ファイル -> リポジトリ
#   bash scripts/sync-claude-settings.sh push [--force]    # リポジトリ -> 実ファイル
#   bash scripts/sync-claude-settings.sh status            # 差分の確認だけ
#
# 実装は Go 側（internal/settings）にある。**この入口を残しているのは、
# dotfilesLink.sh・daily-update.sh・AGENTS.md がこのパスで呼んでいるため。**
#
# なぜシンボリックリンクではないのか、なぜ実ファイルを正とするのかは AGENTS.md の
# 「Claude Code settings.json の同期」節にある。
set -uo pipefail

DOTCTL="$HOME/.local/bin/dotctl"
[ -x "$DOTCTL" ] || DOTCTL="$(command -v dotctl 2>/dev/null || true)"

if [ -z "$DOTCTL" ]; then
  echo "sync-claude-settings: dotctl が見つからない。ビルドする: bash scripts/setup-dotctl.sh" >&2
  exit 1
fi

exec "$DOTCTL" settings sync claude "$@"
