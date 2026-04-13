#!/bin/bash
# Install external Claude Code skills from declarative list
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_FILE="$SCRIPT_DIR/claude-skills.txt"
TARGET_AGENT="claude-code"
# Claude Code reads skills from this directory (see `skills add` output).
SKILLS_INSTALL_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

if [ ! -f "$SKILLS_FILE" ]; then
  echo "Error: $SKILLS_FILE not found"
  exit 1
fi

if ! command -v npx &>/dev/null; then
  echo "Warning: npx not found, skipping Claude Code skills installation"
  exit 0
fi

echo "Installing external Claude Code skills..."

# Check installation status by directory existence instead of `npx skills list`.
# Rationale: `npx skills list --json` occasionally emits non-JSON on stdout
# (e.g. npx cache-warming output on cold runs), which broke jq parsing and
# forced every skill to be reinstalled. Filesystem check is deterministic.
is_skill_installed() {
  local name="$1"
  [ -d "$SKILLS_INSTALL_DIR/$name" ]
}

failures=()
attempted=0
succeeded=0
skipped=0
line_no=0

while IFS= read -r raw_line || [ -n "${raw_line:-}" ]; do
  line_no=$((line_no + 1))

  # Trim leading/trailing spaces first, then skip comments/empty lines.
  line="${raw_line#"${raw_line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" || "$line" == \#* ]] && continue

  # Allow inline comments: "repo --skill name # note"
  line="${line%%[[:space:]]\#*}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue

  read -r -a skill_args <<< "$line"
  # `npx --yes` suppresses the "Need to install ... Ok to proceed?" prompt on
  # cold caches; `skills add --yes` suppresses the CLI's own confirmations.
  cmd=(npx --yes skills add "${skill_args[@]}" -g --agent "$TARGET_AGENT" --yes)

  requested_skills=()
  for ((i = 0; i < ${#skill_args[@]}; i++)); do
    token="${skill_args[$i]}"
    if [[ "$token" == "--skill" || "$token" == "-s" ]]; then
      for ((j = i + 1; j < ${#skill_args[@]}; j++)); do
        next_token="${skill_args[$j]}"
        [[ "$next_token" == -* ]] && break
        requested_skills+=("$next_token")
      done
    fi
  done

  if [ "${#requested_skills[@]}" -gt 0 ]; then
    already_installed=1
    for skill_name in "${requested_skills[@]}"; do
      if ! is_skill_installed "$skill_name"; then
        already_installed=0
        break
      fi
    done
    if [ "$already_installed" -eq 1 ]; then
      echo "  -> skip (already installed): ${requested_skills[*]}"
      skipped=$((skipped + 1))
      continue
    fi
  fi

  attempted=$((attempted + 1))

  echo "  -> ${cmd[*]}"
  if "${cmd[@]}" </dev/null; then
    succeeded=$((succeeded + 1))
  else
    failures+=("line $line_no: $line")
  fi
done < "$SKILLS_FILE"

echo ""
echo "Finished: $succeeded succeeded, $skipped skipped, $attempted attempted."

if [ "${#failures[@]}" -gt 0 ]; then
  echo "Failed skill installs (${#failures[@]}):" >&2
  for failure in "${failures[@]}"; do
    echo "  - $failure" >&2
  done
  exit 1
fi

echo "Done."
