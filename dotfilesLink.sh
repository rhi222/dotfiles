#!/bin/bash
set -euo pipefail

# dotfiles setup script
# Creates symbolic links for all configuration files

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
DC="$DOTFILES_DIR/.config"

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

# リンク先ディレクトリを事前に用意する（fresh 環境では ~/.config 自体が存在しない）
ensure_dirs() {
  mkdir -p ~/.config ~/.config/fish ~/.config/herdr ~/.claude/skills ~/.codex
}

# 単純な src -> dest のリンクを宣言的に列挙する。
# "リポジトリ内のパス|リンク先" のペアで定義し、まとめてリンクする。
# 特殊処理が必要な Claude skills / codex は個別関数（link_claude_skills / setup_codex）で扱う。
link_configs() {
  local links=(
    # Root configuration files
    "$DOTFILES_DIR/.gitconfig|$HOME/.gitconfig"
    "$DC/tmux|$HOME/.config/tmux"
    "$DC/tmux/tmux.conf|$HOME/.tmux.conf"
    "$DOTFILES_DIR/.psqlrc|$HOME/.psqlrc"

    # Claude Code configuration
    "$DC/claude|$HOME/.config/claude"
    "$DC/claude/CLAUDE.md|$HOME/.claude/CLAUDE.md"
    "$DC/claude/settings.json|$HOME/.claude/settings.json"
    "$DC/claude/commands|$HOME/.claude/commands"
    "$DC/claude/agents|$HOME/.claude/agents"

    # Fish shell configuration
    "$DC/fish/config.fish|$HOME/.config/fish/config.fish"
    "$DC/fish/my|$HOME/.config/fish/my"

    # Development tools configuration
    "$DC/ccmanager|$HOME/.config/ccmanager"
    "$DC/ccstatusline|$HOME/.config/ccstatusline"
    "$DC/nvim|$HOME/.config/nvim"
    "$DC/git|$HOME/.config/git"
    "$DC/gwq|$HOME/.config/gwq"
    "$DC/mise|$HOME/.config/mise"
    "$DC/gitui|$HOME/.config/gitui"
    "$DC/lazygit|$HOME/.config/lazygit"
    "$DC/deck|$HOME/.config/deck"
    "$DC/alacritty|$HOME/.config/alacritty"
    "$DC/yazi|$HOME/.config/yazi"

    # herdr: config.toml のみリンク（ディレクトリごとリンクするとログがリポジトリに漏れるため）
    # scripts/ サブディレクトリは popup コマンドから参照するため個別にリンクする
    # （ログは ~/.config/herdr/*.log に出るため scripts/ をリンクしても漏れない）
    "$DC/herdr/config.toml|$HOME/.config/herdr/config.toml"
    "$DC/herdr/scripts|$HOME/.config/herdr/scripts"

    # Custom scripts
    "$DOTFILES_DIR/scripts|$HOME/scripts"
  )
  local pair
  for pair in "${links[@]}"; do
    safe_link "${pair%%|*}" "${pair#*|}"
  done
}

# Skills: ディレクトリごと個別にリンクする（skills 全体をリンクすると入れ子になるため）
link_claude_skills() {
  local skill_dir skill_name
  for skill_dir in "$DC/claude/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    safe_link "$skill_dir" ~/.claude/skills/"$skill_name"
  done
}

# codex: 公式ドキュメントに従いローカル設定を ~/.codex/config.toml に置く
setup_codex() {
  # config.toml は gitignore されているため fresh clone には存在しない。テンプレートから作成する
  if [ ! -e "$DC/codex/config.toml" ]; then
    cp "$DC/codex/config.example.toml" "$DC/codex/config.toml"
    echo "[INFO] .config/codex/config.toml を config.example.toml から作成しました"
  fi
  # 既存の実ファイルがあればタイムスタンプ付きで退避してからリンクする
  if [ -e ~/.codex/config.toml ] && [ ! -L ~/.codex/config.toml ]; then
    local codex_backup
    codex_backup=~/.codex/config.toml.bak."$(date +%Y%m%d%H%M%S)"
    echo "[INFO] 既存の ~/.codex/config.toml を $codex_backup に退避します"
    mv ~/.codex/config.toml "$codex_backup"
  fi
  safe_link "$DC/codex/config.toml" ~/.codex/config.toml
}

# 日報通知スクリプトに実行権限を付与
grant_exec_permissions() {
  chmod +x "$DOTFILES_DIR/scripts/nippo-check.sh" 2>/dev/null || true
  chmod +x "$DOTFILES_DIR/scripts/nippo-cron.sh" 2>/dev/null || true
}

# gitignore されているローカル git 設定の存在チェック（.gitconfig が include している）
warn_missing_local_git() {
  local local_conf
  for local_conf in "$DC/git/config-local" "$DC/git/config-work"; do
    if [ ! -e "$local_conf" ]; then
      echo "[WARN] $local_conf がありません。.config/git/README.md を参照して作成してください" >&2
    fi
  done
}

# 実ディレクトリのためスキップした項目があれば一覧を出して失敗終了する
report_skipped() {
  if [ "${#SKIPPED[@]}" -gt 0 ]; then
    echo "" >&2
    echo "[WARN] 実ディレクトリのためリンクをスキップした項目があります:" >&2
    printf '  %s\n' "${SKIPPED[@]}" >&2
    exit 1
  fi
}

print_next_steps() {
  echo ""
  echo "To install apt packages: ./scripts/apt-setup.sh"
  echo ""
  echo "日報リマインド通知を有効にするには:"
  echo "  1. touch ~/.config/nippo-notify-enabled"
  echo "  2. crontab -e で以下を追加:"
  echo "     0 9,11,13,15,17,19 * * 1-5 \$HOME/scripts/nippo-cron.sh >> \$HOME/.nippo-cron.log 2>&1"
  echo "  無効化: rm ~/.config/nippo-notify-enabled"
}

# --- main ---
ensure_dirs
link_configs
link_claude_skills
setup_codex
grant_exec_permissions
warn_missing_local_git
report_skipped
print_next_steps
