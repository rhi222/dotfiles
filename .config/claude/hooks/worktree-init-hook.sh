#!/usr/bin/env bash
# Claude Code PostToolUse hook (EnterWorktree)
# stdinのhook JSONからworktreeパスを取り出して worktree-init を実行する。
# パスが取れない場合は何もしない（安全側に倒す）
set -euo pipefail

input=$(cat)
# ペイロードのキーはバージョンで変わりうるため候補を順に試す
path=$(echo "$input" | jq -r '
  .tool_response.worktreePath //
  .tool_response.path //
  .tool_response.cwd //
  empty' 2>/dev/null || true)

if [ -z "$path" ] || [ ! -d "$path" ]; then
  exit 0
fi

bash "$HOME/scripts/worktree-init.sh" "$path"
