#!/bin/bash
set -euo pipefail

# dotfiles setup script
# Creates symbolic links for all configuration files

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

safe_link() {
  local src="$1"
  local dest="$2"
  if ln -snf "$src" "$dest"; then
    echo "[OK] $dest -> $src"
  else
    echo "[FAIL] $dest -> $src" >&2
    return 1
  fi
}

# Root configuration files
safe_link "$DOTFILES_DIR/.gitconfig" ~/.gitconfig
safe_link "$DOTFILES_DIR/.tmux.conf" ~/.tmux.conf
safe_link "$DOTFILES_DIR/.psqlrc" ~/.psqlrc

# Claude Code configuration
safe_link "$DOTFILES_DIR/.config/claude" ~/.config/claude
safe_link "$DOTFILES_DIR/.config/claude/CLAUDE.md" ~/.claude/CLAUDE.md
safe_link "$DOTFILES_DIR/.config/claude/settings.json" ~/.claude/settings.json
safe_link "$DOTFILES_DIR/.config/claude/commands" ~/.claude/commands
safe_link "$DOTFILES_DIR/.config/claude/agents" ~/.claude/agents

# codex
# Keep local config at ~/.codex/config.toml per official docs.
mkdir -p ~/.codex
if [ -e ~/.codex/config.toml ] && [ ! -L ~/.codex/config.toml ]; then
  mv ~/.codex/config.toml ~/.codex/config.toml.bak.$(date +%Y%m%d%H%M%S)
fi
safe_link "$DOTFILES_DIR/.config/codex/config.toml" ~/.codex/config.toml

# Fish shell configuration
# Create fish config directory and link individual components
safe_link "$DOTFILES_DIR/.config/fish/config.fish" ~/.config/fish/config.fish
safe_link "$DOTFILES_DIR/.config/fish/my" ~/.config/fish/my

# Development tools configuration
safe_link "$DOTFILES_DIR/.config/ccmanager" ~/.config/ccmanager
safe_link "$DOTFILES_DIR/.config/nvim" ~/.config/nvim
safe_link "$DOTFILES_DIR/.config/git" ~/.config/git
safe_link "$DOTFILES_DIR/.config/gwq" ~/.config/gwq
safe_link "$DOTFILES_DIR/.config/mise" ~/.config/mise
safe_link "$DOTFILES_DIR/.config/gitui" ~/.config/gitui
safe_link "$DOTFILES_DIR/.config/lazygit" ~/.config/lazygit
safe_link "$DOTFILES_DIR/.config/deck" ~/.config/deck
safe_link "$DOTFILES_DIR/.config/alacritty" ~/.config/alacritty
