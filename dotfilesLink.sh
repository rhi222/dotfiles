#!/bin/bash
set -euo pipefail

# dotfiles setup script
# Creates symbolic links for all configuration files

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

SKIPPED=()

safe_link() {
  local src="$1"
  local dest="$2"
  # ln -snf は dest が実ディレクトリだと置き換えずその中にリンクを作ってしまう
  # （例: ~/.config/nvim が実ディレクトリだと ~/.config/nvim/nvim ができる）ため先に検出する
  if [ -d "$dest" ] && [ ! -L "$dest" ]; then
    echo "[SKIP] $dest は実ディレクトリのためリンクしません（退避してから再実行してください）" >&2
    SKIPPED+=("$dest")
    return 0
  fi
  if ln -snf "$src" "$dest"; then
    echo "[OK] $dest -> $src"
  else
    echo "[FAIL] $dest -> $src" >&2
    return 1
  fi
}

# fresh 環境では ~/.config 自体が存在しない
mkdir -p ~/.config

# Root configuration files
safe_link "$DOTFILES_DIR/.gitconfig" ~/.gitconfig
safe_link "$DOTFILES_DIR/.config/tmux" ~/.config/tmux
safe_link "$DOTFILES_DIR/.config/tmux/tmux.conf" ~/.tmux.conf
safe_link "$DOTFILES_DIR/.psqlrc" ~/.psqlrc

# Claude Code configuration
mkdir -p ~/.claude ~/.claude/skills
safe_link "$DOTFILES_DIR/.config/claude" ~/.config/claude
safe_link "$DOTFILES_DIR/.config/claude/CLAUDE.md" ~/.claude/CLAUDE.md
safe_link "$DOTFILES_DIR/.config/claude/settings.json" ~/.claude/settings.json
safe_link "$DOTFILES_DIR/.config/claude/commands" ~/.claude/commands
# Skills: link each skill directory individually to avoid nesting
for skill_dir in "$DOTFILES_DIR/.config/claude/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  safe_link "$skill_dir" ~/.claude/skills/"$skill_name"
done
safe_link "$DOTFILES_DIR/.config/claude/agents" ~/.claude/agents

# codex
# Keep local config at ~/.codex/config.toml per official docs.
mkdir -p ~/.codex
# config.toml は gitignore されているため fresh clone には存在しない。テンプレートから作成する
if [ ! -e "$DOTFILES_DIR/.config/codex/config.toml" ]; then
  cp "$DOTFILES_DIR/.config/codex/config.example.toml" "$DOTFILES_DIR/.config/codex/config.toml"
  echo "[INFO] .config/codex/config.toml を config.example.toml から作成しました"
fi
if [ -e ~/.codex/config.toml ] && [ ! -L ~/.codex/config.toml ]; then
  codex_backup=~/.codex/config.toml.bak."$(date +%Y%m%d%H%M%S)"
  echo "[INFO] 既存の ~/.codex/config.toml を $codex_backup に退避します"
  mv ~/.codex/config.toml "$codex_backup"
fi
safe_link "$DOTFILES_DIR/.config/codex/config.toml" ~/.codex/config.toml

# Fish shell configuration
# Create fish config directory and link individual components
mkdir -p ~/.config/fish
safe_link "$DOTFILES_DIR/.config/fish/config.fish" ~/.config/fish/config.fish
safe_link "$DOTFILES_DIR/.config/fish/my" ~/.config/fish/my

# Development tools configuration
safe_link "$DOTFILES_DIR/.config/ccmanager" ~/.config/ccmanager
safe_link "$DOTFILES_DIR/.config/ccstatusline" ~/.config/ccstatusline
safe_link "$DOTFILES_DIR/.config/nvim" ~/.config/nvim
safe_link "$DOTFILES_DIR/.config/git" ~/.config/git
safe_link "$DOTFILES_DIR/.config/gwq" ~/.config/gwq
safe_link "$DOTFILES_DIR/.config/mise" ~/.config/mise
safe_link "$DOTFILES_DIR/.config/gitui" ~/.config/gitui
safe_link "$DOTFILES_DIR/.config/lazygit" ~/.config/lazygit
safe_link "$DOTFILES_DIR/.config/deck" ~/.config/deck
safe_link "$DOTFILES_DIR/.config/alacritty" ~/.config/alacritty
safe_link "$DOTFILES_DIR/.config/yazi" ~/.config/yazi

# Custom scripts
safe_link "$DOTFILES_DIR/scripts" ~/scripts

# 日報通知スクリプトに実行権限を付与
chmod +x "$DOTFILES_DIR/scripts/nippo-check.sh" 2>/dev/null || true
chmod +x "$DOTFILES_DIR/scripts/nippo-cron.sh" 2>/dev/null || true

# gitignore されているローカル git 設定の存在チェック（.gitconfig が include している）
for local_conf in "$DOTFILES_DIR/.config/git/config-local" "$DOTFILES_DIR/.config/git/config-work"; do
  if [ ! -e "$local_conf" ]; then
    echo "[WARN] $local_conf がありません。.config/git/README.md を参照して作成してください" >&2
  fi
done

if [ "${#SKIPPED[@]}" -gt 0 ]; then
  echo "" >&2
  echo "[WARN] 実ディレクトリのためリンクをスキップした項目があります:" >&2
  printf '  %s\n' "${SKIPPED[@]}" >&2
  exit 1
fi

echo ""
echo "To install apt packages: ./scripts/apt-setup.sh"
echo ""
echo "日報リマインド通知を有効にするには:"
echo "  1. touch ~/.config/nippo-notify-enabled"
echo "  2. crontab -e で以下を追加:"
echo "     0 9,11,13,15,17,19 * * 1-5 \$HOME/scripts/nippo-cron.sh >> \$HOME/.nippo-cron.log 2>&1"
echo "  無効化: rm ~/.config/nippo-notify-enabled"
