#!/bin/bash
# Install all Claude Code skills declared in claude-skills.txt.
# Use `skill-add.sh` for day-to-day additions; this script is for bootstrap
# on a new machine.
#
# claude-skills.txt line format（1形式のみ）:
#   <OWNER/REPO> <skill>[@<version>]
#
# owner は trusted-skill-owners.txt に無ければ拒否する。信頼済みでない skill は
# `skill-vendor.sh add` で vendoring して取り込む（実体をリポジトリにコミットし、
# 更新は git 差分でレビューする）。以前の `local:` 行はこれに吸収して廃止した。
# `local:` は shallow clone の HEAD を毎回取り直して入れるため、pin もレビュー面も
# 無く、3導線のうち最も無制御だった。
#
# Env flags:
#   STRICT=1       : fail hard on missing prereqs (bootstrap)
#   MIGRATE=1      : --force reinstall (migrate from npx skills / inject metadata)
#   SKILL_AGENTS=  : space-separated gh `--agent` targets
#                    (default: "claude-code codex")
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_FILE="${CLAUDE_SKILLS_FILE:-$SCRIPT_DIR/claude-skills.txt}"
MIGRATE="${MIGRATE:-0}"
STRICT="${STRICT:-0}"
SKILL_AGENTS="${SKILL_AGENTS:-claude-code codex}"
REQUIRED_GH_VERSION="2.90.0"

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

# gh skill install のログ置き場。中断（Ctrl-C / timeout）でも一時ファイルが
# 残らないよう、ディレクトリごと EXIT で刈る
INSTALL_LOG_DIR="$(mktemp -d -t claude-skills-install.XXXXXX)"
trap 'rm -rf "$INSTALL_LOG_DIR"' EXIT

# Maps a gh `--agent` value to its user-scope install directory.
# Used for the "already installed" check; gh itself resolves the path
# from the --agent/--scope combination.
agent_target_dir() {
  case "$1" in
    claude-code) echo "$HOME/.claude/skills" ;;
    codex) echo "$HOME/.codex/skills" ;;
    *) echo "" ;;
  esac
}

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

echo "Installing external skills via gh skill (agents: $SKILL_AGENTS)..."

# Runs `gh skill install` for each agent in $SKILL_AGENTS and aggregates
# per-agent results (installed/skipped/failed) into one return code:
#   0   -> at least one agent installed (and none failed)
#   100 -> every agent skipped (already installed)
#   1   -> any agent failed
run_install_for_agents() {
  local skill_name="$1"
  shift
  local -a cmd_prefix=("$@")

  local any_failed=0 all_skipped=1

  for agent in $SKILL_AGENTS; do
    local base_dir
    base_dir="$(agent_target_dir "$agent")"
    if [ -z "$base_dir" ]; then
      echo "  -> ERROR: unknown agent '$agent' (no target dir mapping)" >&2
      any_failed=1
      all_skipped=0
      continue
    fi

    local target="$base_dir/$skill_name"
    if [ "$MIGRATE" != "1" ] && [ -d "$target" ] && [ ! -L "$target" ]; then
      echo "  -> skip ($agent, already installed): $skill_name"
      continue
    fi

    local -a cmd=("${cmd_prefix[@]}" --agent "$agent" --scope user)
    [ "$MIGRATE" = "1" ] && cmd+=(--force)
    echo "  -> ${cmd[*]}"
    local log="$INSTALL_LOG_DIR/install.log"
    if "${cmd[@]}" </dev/null 2>"$log"; then
      cat "$log"
      all_skipped=0
    else
      local rc=$?
      cat "$log" >&2
      echo "  -> ERROR: gh skill install exited $rc (agent=$agent)" >&2
      any_failed=1
      all_skipped=0
    fi
  done

  if [ "$any_failed" = "1" ]; then
    return 1
  elif [ "$all_skipped" = "1" ]; then
    return 100
  else
    return 0
  fi
}

install_remote() {
  local repo="$1" skill_spec="$2" skill_name="$3"
  run_install_for_agents "$skill_name" gh skill install "$repo" "$skill_spec"
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
  read -r repo skill_spec extra <<<"$line"
  if [ -z "${repo:-}" ] || [ -z "${skill_spec:-}" ] || [ -n "${extra:-}" ]; then
    echo "  -> skip (malformed line $line_no): $line"
    failures+=("line $line_no: malformed: $line")
    attempted=$((attempted + 1))
    continue
  fi
  if ! require_trusted_owner "$repo"; then
    echo "  -> skip (untrusted owner, line $line_no): $line"
    failures+=("line $line_no: untrusted owner: $repo")
    attempted=$((attempted + 1))
    continue
  fi
  skill_path="${skill_spec%@*}"
  skill_name="${skill_path##*/}"
  install_remote "$repo" "$skill_spec" "$skill_name" || rc=$?

  case "$rc" in
    0)
      succeeded=$((succeeded + 1))
      attempted=$((attempted + 1))
      ;;
    100) skipped=$((skipped + 1)) ;;
    *)
      failures+=("line $line_no: $line")
      attempted=$((attempted + 1))
      ;;
  esac
done <"$SKILLS_FILE"

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
