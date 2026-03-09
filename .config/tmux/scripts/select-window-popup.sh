#!/usr/bin/env bash

set -u
set -o pipefail

# tmux server は PATH が古いことがあるため、ユーザー側の一般的な bin を補完する。
export PATH="$HOME/.local/bin:$PATH"

resolve_cmd() {
  local name="$1"
  local candidate
  local pattern

  candidate="$(command -v "$name" 2>/dev/null || true)"
  if [ -n "$candidate" ] && [[ "$candidate" != *"/.local/share/mise/shims/"* ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  shopt -s nullglob
  for pattern in "$HOME"/.local/share/mise/installs/*/*/bin/"$name"; do
    candidate="$pattern"
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      shopt -u nullglob
      return 0
    fi
  done
  for pattern in "$HOME"/.local/share/mise/installs/*/*/"$name"; do
    candidate="$pattern"
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob

  candidate="$HOME/.local/share/mise/shims/$name"
  if [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="$(command -v "$name" 2>/dev/null || true)"
  if [ -n "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

show_error() {
  printf '%s\n' "$1"
  printf 'PATH=%s\n' "$PATH"
  printf 'tcmux=%s\n' "${TCMUX_BIN:-not found}"
  printf 'fzf=%s\n' "${FZF_BIN:-not found}"
  printf '\nPress Enter to close...'
  read -r _
}

TCMUX_BIN="$(resolve_cmd tcmux || true)"
FZF_BIN="$(resolve_cmd fzf || true)"

if [ -z "$TCMUX_BIN" ]; then
  show_error "tcmux command not found."
  exit 0
fi

if [ -z "$FZF_BIN" ]; then
  show_error "fzf command not found."
  exit 0
fi

selected="$(
  "$TCMUX_BIN" lsw -A --color=always \
    | "$FZF_BIN" --ansi --layout reverse --color='pointer:24' \
    | cut -d: -f1
)"
status=$?

# fzf cancel/no-select は通常操作として扱う。
if [ "$status" -eq 130 ] || [ "$status" -eq 1 ]; then
  exit 0
fi

if [ "$status" -ne 0 ]; then
  show_error "window selector failed (exit=$status)."
  exit 0
fi

if [ -n "$selected" ]; then
  tmux select-window -t "$selected"
fi
