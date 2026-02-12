#! /bin/bash

# dotfiles setup script
# Creates symbolic links for all configuration files

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Root configuration files
ln -snf $DOTFILES_DIR/.gitconfig ~/.gitconfig
ln -snf $DOTFILES_DIR/.tmux.conf ~/.tmux.conf
ln -snf $DOTFILES_DIR/.psqlrc ~/.psqlrc

# Claude Code configuration
ln -snf $DOTFILES_DIR/.config/claude ~/.config/claude
ln -snf $DOTFILES_DIR/.config/claude/CLAUDE.md ~/.claude/CLAUDE.md
ln -snf $DOTFILES_DIR/.config/claude/settings.json ~/.claude/settings.json
ln -snf $DOTFILES_DIR/.config/claude/commands ~/.claude/commands
ln -snf $DOTFILES_DIR/.config/claude/agents ~/.claude/agents

# codex
# Keep local config at ~/.codex/config.toml per official docs.
mkdir -p ~/.codex
if [ -e ~/.codex/config.toml ] && [ ! -L ~/.codex/config.toml ]; then
  mv ~/.codex/config.toml ~/.codex/config.toml.bak.$(date +%Y%m%d%H%M%S)
fi
ln -snf $DOTFILES_DIR/.config/codex/config.toml ~/.codex/config.toml

# Fish shell configuration
# Create fish config directory and link individual components
ln -snf $DOTFILES_DIR/.config/fish/config.fish ~/.config/fish/config.fish
ln -snf $DOTFILES_DIR/.config/fish/my ~/.config/fish/my

# Development tools configuration
ln -snf $DOTFILES_DIR/.config/ccmanager ~/.config/ccmanager
ln -snf $DOTFILES_DIR/.config/nvim ~/.config/nvim
ln -snf $DOTFILES_DIR/.config/git ~/.config/git
ln -snf $DOTFILES_DIR/.config/gwq ~/.config/gwq
ln -snf $DOTFILES_DIR/.config/mise ~/.config/mise
ln -snf $DOTFILES_DIR/.config/gitui ~/.config/gitui
ln -snf $DOTFILES_DIR/.config/lazygit ~/.config/lazygit
ln -snf $DOTFILES_DIR/.config/deck ~/.config/deck
