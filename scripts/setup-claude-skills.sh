#!/bin/bash
# Install external Claude Code skills from declarative list
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_FILE="$SCRIPT_DIR/claude-skills.txt"
TARGET_AGENT="claude-code"

if [ ! -f "$SKILLS_FILE" ]; then
  echo "Error: $SKILLS_FILE not found"
  exit 1
fi

if ! command -v npx &>/dev/null; then
  echo "Warning: npx not found, skipping Claude Code skills installation"
  exit 0
fi

echo "Installing external Claude Code skills..."

declare -A installed_skills=()
if installed_json="$(npx skills list --json -g -a "$TARGET_AGENT" 2>/dev/null)"; then
  if command -v jq &>/dev/null; then
    mapfile -t installed_skill_names < <(printf '%s\n' "$installed_json" | jq -r '.[].name')
  else
    mapfile -t installed_skill_names < <(
      printf '%s\n' "$installed_json" | sed -n 's/^[[:space:]]*"name":[[:space:]]*"\([^"]*\)".*/\1/p'
    )
  fi

  for skill_name in "${installed_skill_names[@]}"; do
    [ -n "$skill_name" ] && installed_skills["$skill_name"]=1
  done
else
  echo "Warning: failed to list installed skills; duplicate-skip check disabled." >&2
fi

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
  cmd=(npx skills add "${skill_args[@]}" -g --agent "$TARGET_AGENT" --yes)

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
      if [ -z "${installed_skills[$skill_name]+x}" ]; then
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
    for skill_name in "${requested_skills[@]}"; do
      installed_skills["$skill_name"]=1
    done
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
