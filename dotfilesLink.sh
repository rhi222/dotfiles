#! /bin/bash

# dotfiles setup script
# Creates symbolic links for all configuration files

PWD=`pwd`

# Root configuration files
ln -snf $PWD/.gitconfig ~/.gitconfig
ln -snf $PWD/.tmux.conf ~/.tmux.conf
ln -snf $PWD/.psqlrc ~/.psqlrc

# Claude Code configuration
ln -snf $PWD/.config/claude ~/.config/claude
ln -snf $PWD/.config/claude/CLAUDE.md ~/.claude/CLAUDE.md
ln -snf $PWD/.config/claude/settings.json ~/.claude/settings.json
ln -snf $PWD/.config/claude/commands ~/.claude/commands
ln -snf $PWD/.config/claude/agents ~/.claude/agents

# codex
# Keep local config at ~/.codex/config.toml per official docs.
mkdir -p ~/.codex
if [ -e ~/.codex/config.toml ] && [ ! -L ~/.codex/config.toml ]; then
  mv ~/.codex/config.toml ~/.codex/config.toml.bak.$(date +%Y%m%d%H%M%S)
fi
ln -snf $PWD/.config/codex/config.toml ~/.codex/config.toml

# Fish shell configuration
# Create fish config directory and link individual components
ln -snf $PWD/.config/fish/config.fish ~/.config/fish/config.fish
ln -snf $PWD/.config/fish/my ~/.config/fish/my

# Development tools configuration
ln -snf $PWD/.config/ccmanager ~/.config/ccmanager
ln -snf $PWD/.config/nvim ~/.config/nvim
ln -snf $PWD/.config/git ~/.config/git
ln -snf $PWD/.config/gwq ~/.config/gwq
ln -snf $PWD/.config/mise ~/.config/mise
ln -snf $PWD/.config/gitui ~/.config/gitui
ln -snf $PWD/.config/lazygit ~/.config/lazygit
