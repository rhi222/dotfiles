#!/bin/bash
# Add a skill: `gh skill install` + append to claude-skills.txt.
#
# Usage:  bash scripts/skill-add.sh <owner/repo> <skill>[@<version>]
#
# For agentskills.io-unindexed repos, hand-edit claude-skills.txt with a
# `local: <git-url> <sub-path> <skill-name>` line and run setup-claude-skills.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_FILE="$SCRIPT_DIR/claude-skills.txt"

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

if [ "$already_listed" -eq 1 ]; then
  gh skill install "$repo" "$spec" --agent claude-code --scope user --force </dev/null
else
  gh skill install "$repo" "$spec" --agent claude-code --scope user </dev/null
  # Ensure file ends with newline before appending.
  if [ -s "$SKILLS_FILE" ] && [ "$(tail -c1 "$SKILLS_FILE" | wc -l)" -eq 0 ]; then
    printf '\n' >> "$SKILLS_FILE"
  fi
  printf '%s\n' "$entry" >> "$SKILLS_FILE"
  echo "-> appended to $SKILLS_FILE: $entry"
fi

echo "Done. Installed skill: $skill_name"
