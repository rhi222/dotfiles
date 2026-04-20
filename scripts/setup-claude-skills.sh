#!/bin/bash
# Install all Claude Code skills declared in claude-skills.txt.
# Use `skill-add.sh` for day-to-day additions; this script is for
# bootstrap on a new machine and for `local:` entries (not in the
# agentskills.io index).
#
# claude-skills.txt line formats:
#   <OWNER/REPO> <skill>[@<version>]             # remote (gh skill install)
#   local: <git-url> <sub-path> <skill-name>     # git clone + --from-local
#
# Env flags:
#   STRICT=1  : fail hard on missing prereqs (bootstrap)
#   MIGRATE=1 : --force reinstall (migrate from npx skills / inject metadata)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_FILE="$SCRIPT_DIR/claude-skills.txt"
SKILLS_INSTALL_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
LOCAL_CACHE_DIR="${CLAUDE_SKILLS_CACHE:-$HOME/.cache/claude-skills-local}"
MIGRATE="${MIGRATE:-0}"
STRICT="${STRICT:-0}"
REQUIRED_GH_VERSION="2.90.0"

prereq_fail() {
  local msg="$1"
  if [ "$STRICT" = "1" ]; then
    echo "Error: $msg" >&2
    exit 1
  else
    echo "Warning: $msg, skipping" >&2
    exit 0
  fi
}

if [ ! -f "$SKILLS_FILE" ]; then
  echo "Error: $SKILLS_FILE not found" >&2
  exit 1
fi

if ! command -v gh &>/dev/null; then
  prereq_fail "gh not found"
fi

gh_version="$(gh --version | head -1 | awk '{print $3}')"
if [ "$(printf '%s\n%s\n' "$REQUIRED_GH_VERSION" "$gh_version" | sort -V | head -1)" != "$REQUIRED_GH_VERSION" ]; then
  prereq_fail "gh $gh_version < $REQUIRED_GH_VERSION"
fi

if ! gh auth status >/dev/null 2>&1; then
  prereq_fail "gh not authenticated (run 'gh auth login')"
fi

echo "Installing external Claude Code skills via gh skill..."

# Returns:
#   0  -> installed
#   100 -> skipped (already installed)
#   >0 -> failure
install_remote() {
  local repo="$1" skill_spec="$2" skill_name="$3"
  local target="$SKILLS_INSTALL_DIR/$skill_name"

  if [ "$MIGRATE" != "1" ] && [ -d "$target" ] && [ ! -L "$target" ]; then
    echo "  -> skip (already installed): $skill_name"
    return 100
  fi

  local cmd=(gh skill install "$repo" "$skill_spec" --agent claude-code --scope user)
  [ "$MIGRATE" = "1" ] && cmd+=(--force)
  echo "  -> ${cmd[*]}"
  "${cmd[@]}" </dev/null
}

install_local() {
  local git_url="$1" sub_path="$2" skill_name="$3"
  local target="$SKILLS_INSTALL_DIR/$skill_name"

  if [ "$MIGRATE" != "1" ] && [ -d "$target" ] && [ ! -L "$target" ]; then
    echo "  -> skip (already installed): $skill_name"
    return 100
  fi

  mkdir -p "$LOCAL_CACHE_DIR"
  local repo_slug
  repo_slug="$(echo "$git_url" | sed -e 's|^https\?://||' -e 's|^git@||' -e 's|:|/|' -e 's|github\.com/||' -e 's|\.git$||' -e 's|/|__|g')"
  local clone_dir="$LOCAL_CACHE_DIR/$repo_slug"

  if [ -d "$clone_dir/.git" ]; then
    echo "  -> git fetch $clone_dir"
    if ! git -C "$clone_dir" fetch --quiet --depth 1 origin HEAD; then
      echo "  -> ERROR: git fetch failed for $git_url" >&2
      return 1
    fi
    if ! git -C "$clone_dir" reset --quiet --hard FETCH_HEAD; then
      echo "  -> ERROR: git reset --hard FETCH_HEAD failed for $clone_dir" >&2
      return 1
    fi
  else
    echo "  -> git clone $git_url -> $clone_dir"
    if ! git clone --quiet --depth 1 "$git_url" "$clone_dir"; then
      echo "  -> ERROR: git clone failed for $git_url" >&2
      return 1
    fi
  fi

  # sub_path is only used for a pre-flight SKILL.md existence check.
  # `gh skill install --from-local` resolves skills by SKILL.md `name:` field,
  # not by path, so the install command below can only take the skill_name.
  local skill_src="$clone_dir/$sub_path"
  if [ ! -f "$skill_src/SKILL.md" ]; then
    echo "  -> ERROR: $skill_src/SKILL.md not found" >&2
    return 1
  fi

  local cmd=(gh skill install "$clone_dir" "$skill_name" --from-local --agent claude-code --scope user)
  [ "$MIGRATE" = "1" ] && cmd+=(--force)
  echo "  -> ${cmd[*]}"
  local log
  log="$(mktemp -t claude-skills-local.XXXXXX.log)"
  if "${cmd[@]}" </dev/null 2>"$log"; then
    cat "$log"
    rm -f "$log"
    return 0
  else
    local rc=$?
    cat "$log" >&2
    rm -f "$log"
    echo "  -> ERROR: gh skill install --from-local exited $rc" >&2
    return $rc
  fi
}

failures=()
attempted=0
succeeded=0
skipped=0
line_no=0

while IFS= read -r raw_line || [ -n "${raw_line:-}" ]; do
  line_no=$((line_no + 1))

  line="${raw_line#"${raw_line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" || "$line" == \#* ]] && continue

  line="${line%%[[:space:]]\#*}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue

  rc=0
  if [[ "$line" == local:* ]]; then
    body="${line#local:}"
    body="${body#"${body%%[![:space:]]*}"}"
    read -r git_url sub_path skill_name extra <<< "$body"
    if [ -z "${git_url:-}" ] || [ -z "${sub_path:-}" ] || [ -z "${skill_name:-}" ] || [ -n "${extra:-}" ]; then
      echo "  -> skip (malformed local: line $line_no): $line"
      failures+=("line $line_no: malformed local entry: $line")
      attempted=$((attempted + 1))
      continue
    fi
    install_local "$git_url" "$sub_path" "$skill_name"
    rc=$?
  else
    read -r repo skill_spec extra <<< "$line"
    if [ -z "${repo:-}" ] || [ -z "${skill_spec:-}" ] || [ -n "${extra:-}" ]; then
      echo "  -> skip (malformed line $line_no): $line"
      failures+=("line $line_no: malformed: $line")
      attempted=$((attempted + 1))
      continue
    fi
    skill_path="${skill_spec%@*}"
    skill_name="${skill_path##*/}"
    install_remote "$repo" "$skill_spec" "$skill_name"
    rc=$?
  fi

  case "$rc" in
    0) succeeded=$((succeeded + 1)); attempted=$((attempted + 1)) ;;
    100) skipped=$((skipped + 1)) ;;
    *) failures+=("line $line_no: $line"); attempted=$((attempted + 1)) ;;
  esac
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
