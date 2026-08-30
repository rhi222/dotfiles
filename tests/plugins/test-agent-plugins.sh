#!/bin/bash
# agent plugin setupは両hostへlocal marketplace版を入れ、明示時だけupstream版を外す。
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/calls"

make_stub() {
  local path="$1" name="$2"
  cat >"$path" <<EOF
#!/bin/bash
printf '%s %s\n' '$name' "\$*" >>'$LOG'
if [ "\${STUB_CONFIGURED:-}" = 1 ]; then
  case "\$*" in
    'plugin marketplace list --json') printf '%s\n' '{"name": "personal"}' ;;
    'plugin list --json') printf '%s\n' '{"id": "ponytail@personal", "pluginId": "ponytail@personal"}' ;;
  esac
fi
if [ "\${STUB_UPSTREAM:-}" = 1 ]; then
  case "\$*" in
    'plugin marketplace list --json') printf '%s\n' '{"name": "ponytail"}' ;;
    'plugin list --json') printf '%s\n' '{"id": "ponytail@ponytail", "pluginId": "ponytail@ponytail"}' ;;
  esac
fi
EOF
  chmod +x "$path"
}

make_stub "$TMP/claude" claude
make_stub "$TMP/codex" codex

STUB_UPSTREAM=1 CLAUDE_BIN="$TMP/claude" CODEX_BIN="$TMP/codex" \
  AGENT_PLUGIN_MARKETPLACE_ROOT="$ROOT" \
  AGENT_PLUGIN_MARKETPLACE_SOURCE="$ROOT" \
  bash "$ROOT/scripts/setup/agent-plugins.sh" --replace-upstream >/dev/null

grep -Fqx "claude plugin marketplace add $ROOT --scope user" "$LOG"
grep -Fqx "claude plugin install ponytail@personal --scope user" "$LOG"
grep -Fqx "claude plugin uninstall ponytail@ponytail" "$LOG"
grep -Fqx "codex plugin marketplace add $ROOT" "$LOG"
grep -Fqx "codex plugin add ponytail@personal" "$LOG"
grep -Fqx "codex plugin remove ponytail@ponytail" "$LOG"

: >"$LOG"
STUB_CONFIGURED=1 CLAUDE_BIN="$TMP/claude" CODEX_BIN="$TMP/codex" \
  AGENT_PLUGIN_MARKETPLACE_ROOT="$ROOT" \
  AGENT_PLUGIN_MARKETPLACE_SOURCE="$ROOT" \
  bash "$ROOT/scripts/setup/agent-plugins.sh" >/dev/null
[ "$(wc -l <"$LOG")" -eq 4 ] || {
  echo "導入済みpluginを再installした" >&2
  exit 1
}

before="$(wc -l <"$LOG")"
CLAUDE_BIN="$TMP/claude" CODEX_BIN="$TMP/codex" \
  AGENT_PLUGIN_MARKETPLACE_ROOT="$ROOT" \
  AGENT_PLUGIN_MARKETPLACE_SOURCE="$ROOT" \
  bash "$ROOT/scripts/setup/agent-plugins.sh" --dry-run --replace-upstream >/dev/null
after="$(wc -l <"$LOG")"
[ "$before" = "$after" ] || {
  echo "dry-runがcommandを実行した" >&2
  exit 1
}

echo "agent plugin setup tests passed"
