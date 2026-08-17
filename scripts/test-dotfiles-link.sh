#!/bin/bash
# dotfilesLink.sh の関数単体テスト。
# 実際にリンクを張る処理は呼ばず、source して個々の関数だけを検証する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../dotfilesLink.sh"

pass=0
fail=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "NG: $desc"
    fail=$((fail + 1))
  fi
}

# check は真を期待するので、否定はこちらを使う（! はコマンドではないため渡せない）
refute_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if grep -q -- "$needle" <<<"$haystack"; then
    echo "NG: $desc"
    fail=$((fail + 1))
  else
    echo "ok: $desc"
    pass=$((pass + 1))
  fi
}

if [[ ! -f "$SETUP" ]]; then
  echo "ERROR: $SETUP が存在しません"
  exit 1
fi

# shellcheck source=/dev/null  # 検査対象は実行時に決まる相対パス
source "$SETUP"
set +eo pipefail # スクリプト側の set -euo pipefail をテストシェルへ持ち込まない

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# source しただけで main が走っていないこと（走ると実際にリンクが張られてしまう）
check "関数だけが読み込まれ main は走らない" test "$(type -t warn_missing_local_git)" = function

# --- warn_missing_local_git ---
# .gitconfig が無条件 include するのは config-local だけ。config-work は
# config-local 側の includeIf から参照される任意ファイルなので、
# 不在でも警告してはいけない（毎回ノイズが出る）
mkdir -p "$tmp/dc/git"

out=$(DC="$tmp/dc" warn_missing_local_git 2>&1)
check "config-local が無ければ警告する" grep -q "config-local" <<<"$out"

: >"$tmp/dc/git/config-local"
out=$(DC="$tmp/dc" warn_missing_local_git 2>&1)
check "config-local があれば警告しない" test -z "$out"
refute_contains "config-work が無くても警告しない" "config-work" "$out"

# --- link_private_tree ---
# 規則は1つだけ: リンク先が実ディレクトリならその中へ1階層降り、
# 無ければそこで symlink を張る。これでファイル単位とディレクトリ単位が
# 自動で振り分けられる（マニフェストを持たずに済む）。

# ケース1: 親が実在するのでファイル単位、無ければディレクトリごと
priv="$tmp/c1/private"
fh="$tmp/c1/home"
fr="$tmp/c1/repo"
mkdir -p "$priv/home/.claude" "$priv/repo/.config/git" "$priv/repo/.config/ahk/js"
mkdir -p "$fh/.claude" "$fr/.config/git" "$fr/.config/ahk"
echo ctx >"$priv/home/.claude/local-context.md"
echo cfg >"$priv/repo/.config/git/config-local"
echo js >"$priv/repo/.config/ahk/js/a.js"

link_private_tree "$priv/home" "$fh"
link_private_tree "$priv/repo" "$fr"

check "親が実在すればファイル単位でリンクする" test -L "$fh/.claude/local-context.md"
check "リンク先が無ければディレクトリごとリンクする" test -L "$fr/.config/ahk/js"
check "ディレクトリごとリンクした先の中身が読める" test -f "$fr/.config/ahk/js/a.js"
check "リポジトリ側もファイル単位でリンクする" test -L "$fr/.config/git/config-local"
check "ルート自体はリンクに置き換えない" test ! -L "$fr"

# ケース2: passwords/ 相当。README.md が追跡対象なので親はリポジトリに実在する。
# 親をリンクで潰さず、ignore されている子（booking/）だけを張ること。
priv="$tmp/c2/private"
fr="$tmp/c2/repo"
mkdir -p "$priv/repo/.config/ahk/passwords/booking" "$fr/.config/ahk/passwords"
echo pw >"$priv/repo/.config/ahk/passwords/booking/aws.md"
: >"$fr/.config/ahk/passwords/README.md"

link_private_tree "$priv/repo" "$fr"

check "親が実在する場合は子だけをリンクする" test -L "$fr/.config/ahk/passwords/booking"
check "親はリンクに置き換わらない" test ! -L "$fr/.config/ahk/passwords"
check "追跡ファイルはそのまま残る" test -f "$fr/.config/ahk/passwords/README.md"

# ケース3: 集約先の中に相対 symlink があっても辿れること
# （cross-repo-auto-discover/repos.yml は ../cross-repo-investigate/repos.yml への
#   symlink で、集約先の中でも同じ相対関係が成り立つ。実体を2つ持たないための作り）
priv="$tmp/c3/private"
fr="$tmp/c3/repo"
mkdir -p "$priv/repo/.config/skills/inv" "$priv/repo/.config/skills/auto" "$fr/.config/skills"
echo yml >"$priv/repo/.config/skills/inv/repos.yml"
ln -sn ../inv/repos.yml "$priv/repo/.config/skills/auto/repos.yml"

link_private_tree "$priv/repo" "$fr"

check "集約先内の相対 symlink が辿れる" test -f "$fr/.config/skills/auto/repos.yml"
check "実体は1つのまま" test -L "$priv/repo/.config/skills/auto/repos.yml"

# ケース4: リンク先に手書きの実ファイルがあれば退避してからリンクする。
# ln -snf は黙って消すので、import より先に config-local を手書きした端末で
# 内容が失われる。setup_codex と同じくタイムスタンプ付きで退避する。
priv="$tmp/c4/private"
fr="$tmp/c4/repo"
mkdir -p "$priv/repo/.config/git" "$fr/.config/git"
echo frombundle >"$priv/repo/.config/git/config-local"
echo handwritten >"$fr/.config/git/config-local"

link_private_tree "$priv/repo" "$fr"

check "実ファイルはリンクに置き換わる" test -L "$fr/.config/git/config-local"
check "退避ファイルが作られる" \
  bash -c 'compgen -G "'"$fr"'/.config/git/config-local.bak.*" >/dev/null'
check "退避した内容が失われない" \
  bash -c 'grep -q handwritten "'"$fr"'"/.config/git/config-local.bak.*'

# ケース5: 除外パターンはリンクしない
priv="$tmp/c5/private"
fr="$tmp/c5/repo"
mkdir -p "$priv/repo/.config" "$fr/.config"
echo keep >"$priv/repo/.config/real.conf"
echo junk >"$priv/repo/.config/.DS_Store"
echo junk >"$priv/repo/.config/real.conf~"

link_private_tree "$priv/repo" "$fr"

check "通常ファイルはリンクする" test -L "$fr/.config/real.conf"
check ".DS_Store はリンクしない" test ! -e "$fr/.config/.DS_Store"
check "エディタのバックアップはリンクしない" test ! -e "$fr/.config/real.conf~"

# --- link_private_files ---
# 集約先が無い端末では何もせず成功する。旧環境が無い立ち上げでも
# 従来どおり .example からの雛形生成にフォールバックできるようにするため。
out=$(PRIVATE_DIR="$tmp/does-not-exist" link_private_files 2>&1)
check "集約先が無ければ成功する" test $? -eq 0
check "フォールバックすることを伝える" grep -q "フォールバック" <<<"$out"

# home/ と repo/ の両方を配ること
priv="$tmp/pf/private"
fh="$tmp/pf/home"
fr="$tmp/pf/repo"
mkdir -p "$priv/home/.claude" "$priv/repo/.config/git" "$fh/.claude" "$fr/.config/git"
echo ctx >"$priv/home/.claude/local-context.md"
echo cfg >"$priv/repo/.config/git/config-local"

PRIVATE_DIR="$priv" HOME="$fh" DOTFILES_DIR="$fr" link_private_files >/dev/null 2>&1

check "home/ を \$HOME へ配る" test -L "$fh/.claude/local-context.md"
check "repo/ をリポジトリへ配る" test -L "$fr/.config/git/config-local"

# 片方しか無くても失敗しないこと（repo/ だけの集約先を作った端末など）
priv="$tmp/pf2/private"
fr="$tmp/pf2/repo"
mkdir -p "$priv/repo/.config/git" "$fr/.config/git"
echo cfg >"$priv/repo/.config/git/config-local"
PRIVATE_DIR="$priv" HOME="$tmp/pf2/home" DOTFILES_DIR="$fr" link_private_files >/dev/null 2>&1
check "home/ が無くても失敗しない" test $? -eq 0

# --- ensure_dirs ---
# ~/.config/linear と ~/.config/dotfiles を先に実ディレクトリにしておく。
# これが無いと link_private_tree の規則でディレクトリごとリンクされ、
# linear-bootstrap.sh が書く config.json（再生成できる）まで集約先に入り込む。
fakehome="$tmp/ed/home"
mkdir -p "$fakehome"
HOME="$fakehome" ensure_dirs
check "ensure_dirs が ~/.config/linear を作る" test -d "$fakehome/.config/linear"
check "ensure_dirs が ~/.config/dotfiles を作る" test -d "$fakehome/.config/dotfiles"
check "ensure_dirs が ~/.agents/skills を作る" test -d "$fakehome/.agents/skills"

# 親が実ディレクトリなので api-key だけがファイル単位でリンクされること
priv="$tmp/ed/private"
mkdir -p "$priv/home/.config/linear"
echo key >"$priv/home/.config/linear/api-key"
PRIVATE_DIR="$priv" HOME="$fakehome" DOTFILES_DIR="$tmp/ed/repo" \
  link_private_files >/dev/null 2>&1
check "api-key はファイル単位でリンクされる" test -L "$fakehome/.config/linear/api-key"
check "親の .config/linear はリンクに置き換わらない" test ! -L "$fakehome/.config/linear"

# --- link_claude_skills ---
# ~/.claude/skills には2種類が同居する。自作skillへの symlink（リポジトリを指す）と、
# gh skill が入れた外部skillの実ディレクトリ。掃除の対象はリンク切れの symlink だけで、
# 実ディレクトリと生きたリンクには触れてはいけない。
#
# リポジトリから skill を消しても ~/.claude/skills のリンクは残る。Claude Code から
# 読めない亡霊が溜まり続けるので、リンクを張る側で刈る。
sk="$tmp/sk"
mkdir -p "$sk/dc/claude/skills/alive" "$sk/home/.claude/skills"
echo s >"$sk/dc/claude/skills/alive/SKILL.md"

# skill-creator が skill の隣に作る作業ディレクトリ（skill ではないのでリンクしない）
mkdir -p "$sk/dc/claude/skills/alive-workspace/iteration-1"
echo w >"$sk/dc/claude/skills/alive-workspace/iteration-1/notes.md"

# 実体が消えた自作skillのリンク（刈る対象）
ln -sn "$sk/dc/claude/skills/removed" "$sk/home/.claude/skills/removed"
# gh skill が入れた外部skillの実ディレクトリ（残す）
mkdir -p "$sk/home/.claude/skills/external"
echo e >"$sk/home/.claude/skills/external/SKILL.md"
# リポジトリ外を指す生きたリンク（残す）
mkdir -p "$sk/elsewhere/other"
ln -sn "$sk/elsewhere/other" "$sk/home/.claude/skills/other"

DC="$sk/dc" HOME="$sk/home" link_claude_skills >/dev/null 2>&1

check "実体のある自作skillをリンクする" test -L "$sk/home/.claude/skills/alive"
check "リンクした先の中身が読める" test -f "$sk/home/.claude/skills/alive/SKILL.md"
# -e はリンク切れの symlink でも偽になるため「刈れた」の証拠にならない
# （エントリが残っていても通ってしまう）。-L で symlink そのものの不在を見る
check "実体が消えたリンクを刈る" test ! -L "$sk/home/.claude/skills/removed"
check "外部skillの実ディレクトリは消さない" test -f "$sk/home/.claude/skills/external/SKILL.md"
check "リポジトリ外を指す生きたリンクは消さない" test -L "$sk/home/.claude/skills/other"
check "*-workspace はリンクしない" test ! -e "$sk/home/.claude/skills/alive-workspace"

# --- link_codex_skills ---
# Codex の自作 skill はユーザー共通の探索先 ~/.agents/skills へ配置する。
ck="$tmp/ck"
mkdir -p "$ck/dc/codex/skills/refine-pr-description" "$ck/home/.agents/skills"
echo s >"$ck/dc/codex/skills/refine-pr-description/SKILL.md"

ln -sn "$ck/dc/codex/skills/removed" "$ck/home/.agents/skills/removed"
mkdir -p "$ck/home/.agents/skills/external"
echo e >"$ck/home/.agents/skills/external/SKILL.md"

DC="$ck/dc" HOME="$ck/home" link_codex_skills >/dev/null 2>&1

check "Codex skillをユーザー共通の探索先へリンクする" \
  test -L "$ck/home/.agents/skills/refine-pr-description"
check "Codex skillのリンク先が読める" \
  test -f "$ck/home/.agents/skills/refine-pr-description/SKILL.md"
check "Codex skillのリンク切れを刈る" test ! -L "$ck/home/.agents/skills/removed"
check "外部のCodex skill実ディレクトリは消さない" \
  test -f "$ck/home/.agents/skills/external/SKILL.md"

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
