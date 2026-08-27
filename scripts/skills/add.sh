#!/bin/bash
# Add a skill: `gh skill install` + append to claude-skills.txt.
#
# Usage:  bash scripts/skills/add.sh <owner/repo> <skill>[@<version>]
#
# Installs the skill for each agent in $SKILL_AGENTS (default
# "claude-code codex"). The owner must be listed in
# trusted-skill-owners.txt; untrusted owners go through skill-vendor.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_FILE="${CLAUDE_SKILLS_FILE:-$SCRIPT_DIR/../setup/claude-skills.txt}"
SKILL_AGENTS="${SKILL_AGENTS:-claude-code codex}"

usage() {
  cat <<'USAGE' >&2
Usage: skill-add.sh <owner/repo> <skill>[@<version>]

Examples:
  skill-add.sh anthropics/skills frontend-design
  skill-add.sh github/awesome-copilot git-commit@v1.2.0
USAGE
  exit 2
}

[ "$#" -eq 2 ] || usage
repo="$1"
spec="$2"

if [[ "$repo" != */* ]]; then
  echo "Error: first argument must be <owner/repo>, got: $repo" >&2
  usage
fi

# owner allowlist の default-deny。gh を呼ぶ前・claude-skills.txt に追記する前に落とす
# allowlist の判定は dotctl へ寄せている（Go 側の internal/skill）。
# **Shell の lib と Go で二重に実装しないため。** 判定は skill-add と
# setup-claude-skills の両方で要るので、実装を1つに保つほうを取った。
#
# **dotctl が無ければ拒否する（fail-closed）。** allowlist 不在で skill が
# 入らないのは機能が欠けるだけで害がない一方、素通しさせると未検証の skill が
# 毎日自動更新される側に入る。
require_trusted_owner() {
  local repo="$1" dotctl="$HOME/.local/bin/dotctl"
  [ -x "$dotctl" ] || dotctl="$(command -v dotctl 2>/dev/null || true)"
  if [ -z "$dotctl" ]; then
    echo "Error: dotctl が見つからないため owner を検証できない" >&2
    echo "  ビルドする: bash scripts/setup/dotctl.sh" >&2
    return 1
  fi
  "$dotctl" skill trusted "$repo"
}
require_trusted_owner "$repo" || exit 1

if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI not found" >&2
  exit 1
fi

entry="$repo $spec"
skill_name="${spec%@*}"
skill_name="${skill_name##*/}"

already_listed=0
if [ -f "$SKILLS_FILE" ] && grep -Fxq -- "$entry" "$SKILLS_FILE"; then
  already_listed=1
  echo "Note: \"$entry\" already in $SKILLS_FILE; reinstalling with --force"
fi

install_for_agent() {
  local agent="$1"
  local cmd=(gh skill install "$repo" "$spec" --agent "$agent" --scope user)
  [ "$already_listed" -eq 1 ] && cmd+=(--force)
  echo "  -> ${cmd[*]}"
  "${cmd[@]}" </dev/null
}

for agent in $SKILL_AGENTS; do
  install_for_agent "$agent"
done

if [ "$already_listed" -ne 1 ]; then
  # Ensure file ends with newline before appending.
  if [ -s "$SKILLS_FILE" ] && [ "$(tail -c1 "$SKILLS_FILE" | wc -l)" -eq 0 ]; then
    printf '\n' >>"$SKILLS_FILE"
  fi
  printf '%s\n' "$entry" >>"$SKILLS_FILE"
  echo "-> appended to $SKILLS_FILE: $entry"
fi

echo "Done. Installed skill: $skill_name (agents: $SKILL_AGENTS)"
