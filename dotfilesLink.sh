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

# ローカル設定の集約先。実体はここにあり、各所へは symlink を張る。
# 中身の作成と運搬は scripts/private-bundle.sh の担当。
PRIVATE_DIR="${DOTFILES_PRIVATE_DIR:-$HOME/.local/share/dotfiles-private}"

# 集約先に紛れ込んでも配りたくないもの
private_is_excluded() {
  case "$1" in
    .git | .DS_Store | *~ | *.swp) return 0 ;;
  esac
  return 1
}

# 1階層降りるかどうか。両方が「実」ディレクトリのときだけ降りる。
# src 側の -L を見るのは、集約先に置いた symlink（cross-repo-auto-discover/repos.yml）を
# 辿って中身を配ってしまわないため。
private_should_descend() {
  local src="$1" dest="$2"
  [ -d "$src" ] && [ ! -L "$src" ] && [ -d "$dest" ] && [ ! -L "$dest" ]
}

# リンク先が実ファイルなら退避する。ln -snf は黙って消すので、
# import より先に config-local を手書きした端末で内容が失われる。
backup_real_file() {
  local dest="$1" bak
  if [ -e "$dest" ] && [ ! -L "$dest" ] && [ ! -d "$dest" ]; then
    bak="$dest.bak.$(date +%Y%m%d%H%M%S)"
    echo "[INFO] 既存の $dest を $bak に退避します" >&2
    mv "$dest" "$bak"
  fi
}

# ディレクトリ直下の名前を1行ずつ返す。dotglob / nullglob はサブシェルに閉じ込める
# （再帰の途中で shopt を戻すと呼び出し元の状態が壊れるため）
private_children() {
  (
    shopt -s nullglob dotglob
    local c
    for c in "$1"/*; do
      basename "$c"
    done
  )
}

# 集約先のツリーを走査して symlink を張る。
#
# 規則は1つだけ: リンク先が実ディレクトリとして既に存在すれば1階層降り、
# 存在しなければそこでリンクする。これでファイル単位（.config/git/config-local）と
# ディレクトリ単位（ahk-snippets/js）が自動で振り分けられ、マニフェストが要らない。
# ローカル設定を足すときは集約先に置くだけでよく、このスクリプトは変わらない。
#
# ファイル単位で張りたいのに親が新環境に無い場合（~/.config/linear など）は、
# ensure_dirs で先に実ディレクトリを作っておく。制御点をそこに集約している。
link_private_tree() {
  local src_root="$1" dest_root="$2" rel="${3:-}"
  local src="$src_root${rel:+/$rel}"
  local dest="$dest_root${rel:+/$rel}"
  local name

  # rel が空＝ルート。$HOME やリポジトリルートをリンクで置き換えないよう必ず降りる
  if [ -n "$rel" ] && ! private_should_descend "$src" "$dest"; then
    backup_real_file "$dest"
    safe_link "$src" "$dest"
    return 0
  fi

  while IFS= read -r name; do
    [ -n "$name" ] || continue
    private_is_excluded "$name" && continue
    link_private_tree "$src_root" "$dest_root" "${rel:+$rel/}$name"
  done < <(private_children "$src")
  return 0
}

# 集約先のローカル設定を各所へ配る。
# 集約先が無い端末（旧環境からの移植をしていない立ち上げ）では何もしない。
# setup_local_configs / setup_git_hooks が .example から雛形を作る従来の経路に落ちる。
link_private_files() {
  if [ ! -d "$PRIVATE_DIR" ]; then
    echo "[INFO] $PRIVATE_DIR がありません。ローカル設定は雛形生成にフォールバックします" >&2
    return 0
  fi
  if [ -d "$PRIVATE_DIR/home" ]; then
    link_private_tree "$PRIVATE_DIR/home" "$HOME"
  fi
  if [ -d "$PRIVATE_DIR/repo" ]; then
    link_private_tree "$PRIVATE_DIR/repo" "$DOTFILES_DIR"
  fi
  return 0
}

# リンク先ディレクトリを事前に用意する（fresh 環境では ~/.config 自体が存在しない）
#
# ~/.config/dotfiles と ~/.config/linear は、集約先から「ファイル単位で」リンクを
# 張るために先に実ディレクトリにしておく。無いままだと link_private_tree の規則で
# ディレクトリごとリンクされ、linear-bootstrap.sh が書く config.json（再生成できる）まで
# 集約先に入り込んで zip に混ざる。
ensure_dirs() {
  mkdir -p ~/.config ~/.config/fish ~/.config/herdr ~/.claude/skills ~/.codex \
    ~/.config/dotfiles ~/.config/linear
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
    # settings.json は symlink にできないため setup_claude_settings で別途同期する
    "$DC/claude|$HOME/.config/claude"
    "$DC/claude/CLAUDE.md|$HOME/.claude/CLAUDE.md"
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
#
# 張る前にリンク切れを刈る。リポジトリから skill を消してもリンクは残るため、
# Claude Code から読めない亡霊が溜まり続ける（trend/review/report を畳んだときに
# 実際に5本残った）。
#
# **刈る対象はリンク切れの symlink だけ。** ~/.claude/skills には gh skill が入れた
# 外部skillの実ディレクトリが同居しているので、実体や生きたリンクに触れてはいけない。
link_claude_skills() {
  local skill_dir skill_name link
  for link in ~/.claude/skills/*; do
    # -L かつ -e が偽 == リンク切れ。実ディレクトリは -L で落ちる
    if [ -L "$link" ] && [ ! -e "$link" ]; then
      rm -f "$link"
      echo "[PRUNE] $link （リンク切れ）"
    fi
  done
  for skill_dir in "$DC/claude/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    safe_link "$skill_dir" ~/.claude/skills/"$skill_name"
  done
}

# Claude Code の settings.json はコピーで同期する。
# Claude Code が /config の操作などで実行時に書き戻す際、一時ファイル + rename で
# 置き換えるため symlink にしても必ず実ファイル化してしまう（書き込まれない
# CLAUDE.md や commands/ は symlink のままでよい）。詳細は sync-claude-settings.sh 冒頭。
setup_claude_settings() {
  if ! bash "$DOTFILES_DIR/scripts/sync-claude-settings.sh" push; then
    echo "[WARN] ~/.claude/settings.json は更新しませんでした" >&2
    echo "       実ファイル側を残す:     bash scripts/sync-claude-settings.sh pull" >&2
    echo "       リポジトリ版で上書き:   bash scripts/sync-claude-settings.sh push --force" >&2
  fi
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

# yazi のプラグイン実体を配置する。
# plugins/ は gitignore しているので fresh clone には宣言（package.toml）だけがあり、
# init.lua が require("git") するため実体が欠けていると yazi が起動そのものに失敗する。
# gh 拡張や claude skill のように「無ければ機能が欠けるだけ」ではないので、
# 手動手順ではなくリンク作成と同じ流れで通す。
#
# ネットワーク断でリンク作業まで巻き込まないよう、失敗しても続行する。
setup_yazi_plugins() {
  if ! bash "$DOTFILES_DIR/scripts/setup-yazi-plugins.sh"; then
    echo "[WARN] yazi のプラグイン配置に失敗しました（yazi が起動できない状態です）" >&2
    echo "       復旧: bash scripts/setup-yazi-plugins.sh" >&2
  fi
}

# pre-commit hook を有効にする。このリポジトリは public なので、社内固有情報を
# 含むコミットを commit の手前で止める。詳細は scripts/secret-scan.sh 冒頭。
#
# 機密語辞書はリポジトリではなく ~/.config/dotfiles/ に置く。辞書そのものが
# 機密なので、コミットすると分離した意味が消えるため。
setup_git_hooks() {
  git -C "$DOTFILES_DIR" config core.hooksPath scripts/hooks
  chmod +x "$DOTFILES_DIR/scripts/hooks/pre-commit" 2>/dev/null || true

  local patterns="$HOME/.config/dotfiles/secret-patterns.txt"
  if [ ! -f "$patterns" ]; then
    mkdir -p "$(dirname "$patterns")"
    cp "$DOTFILES_DIR/scripts/secret-patterns.txt.example" "$patterns"
    echo "[INFO] $patterns を雛形から作成しました" >&2
    echo "       社内固有の語を追記してください（この内容はコミットされません）" >&2
  fi
}

# gitignore されているローカル設定を雛形から作る。
# いずれも社内固有の値を持つため、リポジトリには .example だけを置いている。
setup_local_configs() {
  local pairs=(
    "$DC/nvim/lua/my/local_config.lua.example|$DC/nvim/lua/my/local_config.lua"
    # local-context.md の置き場所は ~/.claude/ 直下（リポジトリ外）。
    # .config/claude/ は ~/.config/claude へリンクされるので、そこに置くとリポジトリ内に現れる
    "$DC/claude/local-context.md.example|$HOME/.claude/local-context.md"
  )
  local pair src dest
  for pair in "${pairs[@]}"; do
    src="${pair%%|*}"
    dest="${pair##*|}"
    if [ ! -e "$dest" ] && [ -e "$src" ]; then
      cp "$src" "$dest"
      echo "[INFO] $dest を雛形から作成しました" >&2
      echo "       社内固有の値を埋めてください（この内容はコミットされません）" >&2
    fi
  done
}

# 日報通知スクリプトに実行権限を付与
grant_exec_permissions() {
  chmod +x "$DOTFILES_DIR/scripts/nippo-check.sh" 2>/dev/null || true
  chmod +x "$DOTFILES_DIR/scripts/nippo-cron.sh" 2>/dev/null || true
  chmod +x "$DOTFILES_DIR/scripts/worktree-init.sh" 2>/dev/null || true
  chmod +x "$DOTFILES_DIR/scripts/test-worktree-init.sh" 2>/dev/null || true
  # Linear個人司令塔のcronスクリプト
  chmod +x "$DOTFILES_DIR/scripts/linear-sweep.sh" 2>/dev/null || true
  chmod +x "$DOTFILES_DIR/scripts/linear-dispatch-cron.sh" 2>/dev/null || true
  chmod +x "$DOTFILES_DIR/scripts/linear-bootstrap.sh" 2>/dev/null || true
}

# gitignore されているローカル git 設定の存在チェック。
#
# config-work は対象にしない。.gitconfig が無条件で include するのは config-local だけで、
# 業務用設定は config-local 側の includeIf から参照する任意の仕組みになっている
# （includeIf を書かない端末では config-work は読まれないので、無くて正しい）。
# 以前は両方を要求していたため、使っていない端末でも毎回 WARN が出ていた。
warn_missing_local_git() {
  if [ ! -e "$DC/git/config-local" ]; then
    echo "[WARN] $DC/git/config-local がありません。user.name / user.email を書いてください" >&2
    echo "       業務用の設定を分けたい場合は、このファイルに includeIf で config-work を足します" >&2
  fi
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

main() {
  ensure_dirs
  # link_configs より先に張る。cross-repo-auto-discover は
  # 「集約先 → リポジトリ内 → ~/.claude/skills」の二段リンクになるため、
  # link_claude_skills が走る時点で一段目が済んでいる必要がある
  link_private_files
  link_configs
  link_claude_skills
  setup_claude_settings
  setup_codex
  # link_configs で ~/.config/yazi を張った後に呼ぶ（package.toml がそこにある）
  setup_yazi_plugins
  setup_git_hooks
  setup_local_configs
  grant_exec_permissions
  warn_missing_local_git
  report_skipped
  print_next_steps
}

# source されたときは実行しない。テストから関数だけを呼べるようにするため
# （このスクリプトは実際にリンクを張るので、読み込むだけで走ると環境を壊す）
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
