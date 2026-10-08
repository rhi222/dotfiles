#!/bin/bash
# Codex の session identity を Herdr へ報告する。
# conversation の復元は Herdr 本体の native agent restore が担当する。
set -uo pipefail

[[ "${HERDR_ENV:-}" == 1 ]] || exit 0
[[ -n "${HERDR_PANE_ID:-}" ]] || exit 0

# mise upgrade は旧版の install dir を消すが、稼働中の server が配った
# HERDR_BIN_PATH は古いままなので、消えていたら PATH 上の herdr を使う。
herdr_bin=${HERDR_BIN_PATH:-}
[[ -x "$herdr_bin" ]] || herdr_bin=$(command -v herdr) || exit 0

payload=$(cat)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
[[ -n "$session_id" && -n "$transcript" ]] || exit 0

# resume した旧 session の遅延 hook が新 session を上書きしないようにする。
if [[ -n "${CODEX_THREAD_ID:-}" && "$CODEX_THREAD_ID" != "$session_id" ]]; then
  exit 0
fi

"$herdr_bin" pane report-agent-session "$HERDR_PANE_ID" \
  --source herdr:codex \
  --agent codex \
  --seq "$(date +%s%N)" \
  --agent-session-id "$session_id" >/dev/null 2>&1 || true
