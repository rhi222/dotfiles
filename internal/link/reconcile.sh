#!/bin/bash
set -euo pipefail

# Repeatable symlink reconciliation. The public entrypoint is ../../dotfilesLink.sh.

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DC="$DOTFILES_DIR/.config"

SKIPPED=()
LINKED=0
UNCHANGED=0

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
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    UNCHANGED=$((UNCHANGED + 1))
    return 0
  fi
  if ln -snf "$src" "$dest"; then
    LINKED=$((LINKED + 1))
    echo "[LINK] $dest -> $src"
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
# 集約先が無い端末では何もしない。雛形生成はbootstrapの明示実行に任せる。
link_private_files() {
  if [ ! -d "$PRIVATE_DIR" ]; then
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
  mkdir -p ~/.config ~/.config/fish ~/.config/herdr ~/.claude/skills ~/.codex ~/.codex/rules ~/.agents/skills \
    ~/.config/dotfiles ~/.config/linear ~/.config/psql
}

# 単純な src -> dest のリンクを宣言的に列挙する。
# "リポジトリ内のパス|リンク先" のペアで定義し、まとめてリンクする。
# 特殊処理が必要な Claude skills / Codex は個別関数
# （link_claude_skills / link_codex_config）で扱う。
link_configs() {
  local links=(
    # Root configuration files
    "$DOTFILES_DIR/.gitconfig|$HOME/.gitconfig"
    "$DC/tmux|$HOME/.config/tmux"
    "$DC/tmux/tmux.conf|$HOME/.tmux.conf"
    "$DC/psql/psqlrc|$HOME/.psqlrc"

    # Claude Code configuration
    # settings.json は symlink にできないため setup_claude_settings で別途同期する
    "$DC/claude|$HOME/.config/claude"
    "$DC/claude/CLAUDE.md|$HOME/.claude/CLAUDE.md"
    "$DC/claude/commands|$HOME/.claude/commands"
    "$DC/claude/agents|$HOME/.claude/agents"

    # Fish shell configuration
    # fish_plugins は fisher の宣言リスト。fisher は `printf ... > $fish_plugins` で
    # 書き戻すので symlink を貫通し、リンクは外れない（実体を消すのは全プラグインを
    # remove したときだけ）。
    "$DC/fish/config.fish|$HOME/.config/fish/config.fish"
    "$DC/fish/fish_plugins|$HOME/.config/fish/fish_plugins"
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

# vendored な外部 skill を張る。自作 skill と同じディレクトリ単位のリンクで、
# 張り先を引数で受ける（~/.claude/skills と ~/.agents/skills の両方に張るため）。
#
# 外部 skill は SKILL_AGENTS の既定で claude-code と codex の両方に入っているので、
# vendored に移しても見えるものを減らさない。codex 側を ~/.codex/skills ではなく
# ~/.agents/skills にするのは、後者が Codex のユーザー共通探索先で、自作 codex skill が
# 既にそこへ張られているため。
#
# gh が入れた実ディレクトリを潰さないガードは safe_link 側にあるのでここには要らない。
link_vendor_skills_into() {
  local target_base="$1" skill_dir skill_name
  [ -d "$DC/claude/skills-vendor" ] || return 0
  for skill_dir in "$DC/claude/skills-vendor"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    # 自作と同名だと、後から張った方で上書きされてどちらが有効か分からなくなる
    if [ -d "$DC/claude/skills/$skill_name" ]; then
      echo "[SKIP] $skill_name は自作 skill と名前が衝突しています" >&2
      SKIPPED+=("$target_base/$skill_name")
      continue
    fi
    safe_link "$skill_dir" "$target_base/$skill_name"
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
    # skill-creator は skill の隣に <name>-workspace/ を作る。skill ではないので
    # リンクしない（リンクすると、作業場を消したあと亡霊リンクが残る実例があった）
    case "$skill_name" in *-workspace) continue ;; esac
    safe_link "$skill_dir" ~/.claude/skills/"$skill_name"
  done
  link_vendor_skills_into ~/.claude/skills
}

# Codex のユーザー共通 skill は公式の探索先 ~/.agents/skills に個別リンクする。
# ディレクトリ全体をリンクしないのは、外部から導入した skill と同居できるようにするため。
# Claude skills と同じく、実ディレクトリと生きた外部リンクには触れず、リンク切れだけを刈る。
link_codex_skills() {
  local skill_dir skill_name link
  for link in ~/.agents/skills/*; do
    if [ -L "$link" ] && [ ! -e "$link" ]; then
      rm -f "$link"
      echo "[PRUNE] $link （リンク切れ）"
    fi
  done
  for skill_dir in "$DC/codex/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    case "$skill_name" in *-workspace) continue ;; esac
    safe_link "$skill_dir" ~/.agents/skills/"$skill_name"
  done
  link_vendor_skills_into ~/.agents/skills
}

# fish_plugins は link_configs でリンクするが、safe_link の `ln -snf` は実ファイルを
# 黙って消す。この宣言リストは端末ごとに実体が先にあり、しかも「その端末に何が
# 入っているか」の唯一の記録なので、消えると別端末の宣言が失われる。
#
# 中身が同じなら退避しない。両端末とも同じ3つという通常ケースで、初回実行のたびに
# 意味のない .bak が増えるのを避ける。
backup_fish_plugins() {
  local live=~/.config/fish/fish_plugins
  local repo="$DC/fish/fish_plugins"

  [ -e "$live" ] || return 0
  [ -L "$live" ] && return 0
  if [ -f "$repo" ] && cmp -s "$live" "$repo"; then
    return 0
  fi

  local backup
  backup="$live.bak.$(date +%Y%m%d%H%M%S)"
  echo "[INFO] 既存の $live を $backup に退避します（リポジトリの宣言と内容が異なります）"
  mv "$live" "$backup"
}

# Codex config の内容は初期化しない。repo側の実体がある場合だけlinkをreconcileする。
# 無い状態でlive側を張り替えると、migration後の設定をexample相当へ戻してしまうため。
link_codex_config() {
  if [ -e "$DC/codex/config.toml" ]; then
    backup_real_file ~/.codex/config.toml
    safe_link "$DC/codex/config.toml" ~/.codex/config.toml
  else
    echo "[WARN] $DC/codex/config.toml が無いためCodex configのlinkを変更しません" >&2
    echo "       初期化: bash scripts/bootstrap.sh" >&2
  fi
  # TUIが自動生成する default.rules と共存させ、repository管理分だけを別fileで配る。
  mkdir -p ~/.codex/rules
  backup_real_file ~/.codex/rules/dotfiles.rules
  safe_link "$DC/codex/rules/dotfiles.rules" ~/.codex/rules/dotfiles.rules
  link_codex_skills
}

# pre-commit hook を有効にする。このリポジトリは public なので、社内固有情報を
# 含むコミットを commit の手前で止める。詳細は scripts/secret-scan.sh 冒頭。
configure_git_hooks() {
  git -C "$DOTFILES_DIR" config core.hooksPath scripts/hooks
  chmod +x "$DOTFILES_DIR/scripts/hooks/pre-commit" 2>/dev/null || true
}

# 日報通知スクリプトに実行権限を付与
grant_exec_permissions() {
  chmod +x "$DOTFILES_DIR/scripts/nippo-check.sh" 2>/dev/null || true
  chmod +x "$DOTFILES_DIR/scripts/nippo-cron.sh" 2>/dev/null || true
  chmod +x "$DOTFILES_DIR/scripts/worktree-init.sh" 2>/dev/null || true
  chmod +x "$DOTFILES_DIR/tests/worktree/test-worktree-init.sh" 2>/dev/null || true
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

link_main() {
  SKIPPED=()
  LINKED=0
  UNCHANGED=0
  ensure_dirs
  # link_configs より先に張る。cross-repo-auto-discover は
  # 「集約先 → リポジトリ内 → ~/.claude/skills」の二段リンクになるため、
  # link_claude_skills が走る時点で一段目が済んでいる必要がある
  link_private_files
  # link_configs が fish_plugins を張る前に、内容の違う実ファイルを退避する
  backup_fish_plugins
  link_configs
  link_claude_skills
  link_codex_config
  configure_git_hooks
  grant_exec_permissions
  warn_missing_local_git
  echo "dotfilesLink: LINKED=$LINKED UNCHANGED=$UNCHANGED SKIPPED=${#SKIPPED[@]}"
  report_skipped
}

# 実行判断は公開entrypointの dotfilesLink.sh が行う。このファイルは関数定義だけを持つ。
