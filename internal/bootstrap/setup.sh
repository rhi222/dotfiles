#!/bin/bash
set -euo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../link/reconcile.sh
source "$BOOTSTRAP_DIR/../link/reconcile.sh"

# Claude Codeがrenameで書き戻すsettingsはsymlinkにできないため、初期構築時だけcopy同期する。
setup_claude_settings() {
  if ! bash "$DOTFILES_DIR/scripts/settings/sync-claude.sh" push; then
    echo "[WARN] ~/.claude/settings.json は更新しませんでした" >&2
    echo "       実ファイル側を残す:     bash scripts/settings/sync-claude.sh pull" >&2
    echo "       リポジトリ版で上書き:   bash scripts/settings/sync-claude.sh push --force" >&2
  fi
}

# repo側のignore対象configを初期化する。migration済みのlive設定をexampleより優先する。
init_codex_config() {
  local repo="$DC/codex/config.toml"
  local live="$HOME/.codex/config.toml"

  [ ! -e "$repo" ] || return 0
  mkdir -p "$(dirname "$repo")"
  if [ -f "$live" ]; then
    cp -L "$live" "$repo"
    echo "[INFO] 既存の $live を $repo へ取り込みました"
  else
    cp "$DC/codex/config.example.toml" "$repo"
    echo "[INFO] $repo を config.example.toml から作成しました"
  fi
}

# 機密語辞書はrepo外に置き、初回だけ雛形を作る。
init_secret_patterns() {
  local patterns="$HOME/.config/dotfiles/secret-patterns.txt"
  if [ ! -f "$patterns" ]; then
    mkdir -p "$(dirname "$patterns")"
    cp "$DOTFILES_DIR/scripts/repository/secret-patterns.txt.example" "$patterns"
    echo "[INFO] $patterns を雛形から作成しました" >&2
    echo "       社内固有の語を追記してください（この内容はコミットされません）" >&2
  fi
}

# gitignoreされているローカル設定を初回だけ雛形から作る。
init_local_configs() {
  local pairs=(
    "$DC/nvim/lua/my/local_config.lua.example|$DC/nvim/lua/my/local_config.lua"
    "$DC/claude/local-context.md.example|$HOME/.claude/local-context.md"
    "$DC/psql/psqlrc.local.example|$HOME/.config/psql/psqlrc.local"
    "$DOTFILES_DIR/scripts/db/ssh-tunnel.tsv.example|$HOME/.config/dotfiles/ssh-tunnel.tsv"
  )
  local pair src dest
  for pair in "${pairs[@]}"; do
    src="${pair%%|*}"
    dest="${pair##*|}"
    if [ ! -e "$dest" ] && [ -e "$src" ]; then
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
      echo "[INFO] $dest を雛形から作成しました" >&2
      echo "       社内固有の値を埋めてください（この内容はコミットされません）" >&2
    fi
  done
}

setup_yazi_plugins() {
  if ! bash "$DOTFILES_DIR/scripts/setup/yazi-plugins.sh"; then
    echo "[WARN] yazi のプラグイン配置に失敗しました（yazi が起動できない状態です）" >&2
    echo "       復旧: bash scripts/setup/yazi-plugins.sh" >&2
  fi
}

print_next_steps() {
  echo ""
  echo "To install apt packages: ./scripts/setup/apt.sh"
  echo ""
  echo "日報リマインド通知を有効にするには:"
  echo "  1. touch ~/.config/nippo-notify-enabled"
  echo "  2. crontab -e で以下を追加:"
  echo "     0 9,11,13,15,17,19 * * 1-5 \$HOME/scripts/nippo/notify-cron.sh >> \$HOME/.nippo-cron.log 2>&1"
  echo "  無効化: rm ~/.config/nippo-notify-enabled"
}

bootstrap_main() {
  ensure_dirs
  # import済みの実体を先に配り、存在するローカル設定を雛形で作り直さない。
  if [ ! -d "$PRIVATE_DIR" ]; then
    echo "[INFO] $PRIVATE_DIR がありません。ローカル設定は雛形から初期化します" >&2
  fi
  link_private_files
  init_codex_config
  init_secret_patterns
  init_local_configs
  link_main
  setup_claude_settings
  setup_yazi_plugins
  print_next_steps
}
