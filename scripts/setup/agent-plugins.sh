#!/bin/bash
# repo-local marketplaceからreview済みagent pluginをClaude/Codexへ導入する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_ROOT="${AGENT_PLUGIN_MARKETPLACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
MARKETPLACE_SOURCE="${AGENT_PLUGIN_MARKETPLACE_SOURCE:-rhi222/dotfiles}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CODEX_BIN="${CODEX_BIN:-codex}"
SELECTOR="ponytail@personal"
DRY_RUN=0
REPLACE_UPSTREAM=0

usage() {
  echo "Usage: bash scripts/setup/agent-plugins.sh [--dry-run] [--replace-upstream]" >&2
  exit 2
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --replace-upstream) REPLACE_UPSTREAM=1 ;;
    -h | --help) usage ;;
    *) usage ;;
  esac
done

run() {
  printf '  ->'
  printf ' %q' "$@"
  printf '\n'
  [ "$DRY_RUN" -eq 1 ] || "$@"
}

has_json_value() {
  local pattern="$1"
  shift
  "$@" 2>/dev/null | grep -Eq "$pattern"
}

install_claude() {
  if [ "$DRY_RUN" -eq 1 ] || ! has_json_value '"name"[[:space:]]*:[[:space:]]*"personal"' "$CLAUDE_BIN" plugin marketplace list --json; then
    run "$CLAUDE_BIN" plugin marketplace add "$MARKETPLACE_SOURCE" --scope user
  else
    echo "  [OK] marketplace personal"
  fi
  if [ "$DRY_RUN" -eq 1 ] || ! has_json_value '"id"[[:space:]]*:[[:space:]]*"ponytail@personal"' "$CLAUDE_BIN" plugin list --json; then
    run "$CLAUDE_BIN" plugin install "$SELECTOR" --scope user
  else
    echo "  [OK] $SELECTOR"
  fi
}

install_codex() {
  if [ "$DRY_RUN" -eq 1 ] || ! has_json_value '"name"[[:space:]]*:[[:space:]]*"personal"' "$CODEX_BIN" plugin marketplace list --json; then
    run "$CODEX_BIN" plugin marketplace add "$MARKETPLACE_SOURCE"
  else
    echo "  [OK] marketplace personal"
  fi
  if [ "$DRY_RUN" -eq 1 ] || ! has_json_value '"pluginId"[[:space:]]*:[[:space:]]*"ponytail@personal"' "$CODEX_BIN" plugin list --json; then
    run "$CODEX_BIN" plugin add "$SELECTOR"
  else
    echo "  [OK] $SELECTOR"
  fi
}

remove_claude_upstream() {
  if [ "$DRY_RUN" -eq 1 ] || has_json_value '"id"[[:space:]]*:[[:space:]]*"ponytail@ponytail"' "$CLAUDE_BIN" plugin list --json; then
    run "$CLAUDE_BIN" plugin uninstall ponytail@ponytail
  fi
  if [ "$DRY_RUN" -eq 1 ] || has_json_value '"name"[[:space:]]*:[[:space:]]*"ponytail"' "$CLAUDE_BIN" plugin marketplace list --json; then
    run "$CLAUDE_BIN" plugin marketplace remove ponytail
  fi
}

remove_codex_upstream() {
  if [ "$DRY_RUN" -eq 1 ] || has_json_value '"pluginId"[[:space:]]*:[[:space:]]*"ponytail@ponytail"' "$CODEX_BIN" plugin list --json; then
    run "$CODEX_BIN" plugin remove ponytail@ponytail
  fi
  if [ "$DRY_RUN" -eq 1 ] || has_json_value '"name"[[:space:]]*:[[:space:]]*"ponytail"' "$CODEX_BIN" plugin marketplace list --json; then
    run "$CODEX_BIN" plugin marketplace remove ponytail
  fi
}

if [ ! -f "$REPO_ROOT/.agents/plugins/marketplace.json" ] ||
  [ ! -f "$REPO_ROOT/.claude-plugin/marketplace.json" ]; then
  echo "Error: marketplace manifest が見つかりません: $REPO_ROOT" >&2
  exit 1
fi

echo "Claude Code: $SELECTOR"
if command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  install_claude
  if [ "$REPLACE_UPSTREAM" -eq 1 ]; then
    remove_claude_upstream
  fi
else
  echo "  [SKIP] claude がありません"
fi

echo "Codex: $SELECTOR"
if command -v "$CODEX_BIN" >/dev/null 2>&1; then
  install_codex
  if [ "$REPLACE_UPSTREAM" -eq 1 ]; then
    remove_codex_upstream
  fi
else
  echo "  [SKIP] codex がありません"
fi

if [ "$DRY_RUN" -eq 0 ]; then
  echo "導入後はClaude/Codexを再起動する。Codexでは /hooks でvendor版hookを確認してtrustする。"
fi
