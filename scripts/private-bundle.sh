#!/bin/bash
# gitignore しているローカル設定・機密ファイルを1ディレクトリに集約し、端末間で運ぶ。
#
#   bash scripts/private-bundle.sh adopt [--execute]   # 散らばった実体を集約先へ（旧環境で1回）
#   bash scripts/private-bundle.sh export [--out PATH] # パスワード付き zip に固める
#   bash scripts/private-bundle.sh import <zip> [--force]
#   bash scripts/private-bundle.sh status
#
# 集約先が実体で、各所へは dotfilesLink.sh が symlink を張る。
# どこを編集しても集約先が最新になるので、export はいつ走らせてもよい。
#
# 移植対象の宣言（ADOPT_ENTRIES）はこのスクリプトだけが持つ。dotfilesLink.sh は
# 「集約先にあるものを配る」しか知らないので、対象が増えても向こうは変わらない。
#
# パスに社内名を含むものは既に .gitignore に書かれている。この一覧を public に
# 置いても新たな漏洩は起きない。
#
# 環境変数:
#   DOTFILES_PRIVATE_DIR         集約先（既定: ~/.local/share/dotfiles-private）
#   PRIVATE_BUNDLE_ZIP_PASSWORD  テスト専用。zip -e の代わりに -P を使う
set -uo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_PRIVATE_DIR:-$HOME/.local/share/dotfiles-private}"

# <kind>:<リポジトリ or $HOME からの相対パス>
# kind に @under を付けると「そのディレクトリ直下のうち git が ignore しているもの」を拾う。
# passwords/ は README.md と .gitkeep が追跡対象で中身だけが ignore され、
# 子の名前は端末ごとに違いうるのでハードコードしない。
ADOPT_ENTRIES=(
  "home:.claude/local-context.md"
  "home:.config/linear/api-key"
  "home:.config/dotfiles/secret-patterns.txt"
  "repo:.config/git/config-local"
  "repo:.config/git/config-work"
  "repo:.config/fish/my/conf.d/99-local.fish"
  "repo:.config/nvim/lua/my/local_config.lua"
  "repo:.config/claude/skills/cross-repo-investigate/repos.yml"
  "repo:.config/claude/skills/esa-weekly-report/esa-weekly-report-posts.json"
  "repo:.config/claude/skills/cross-repo-auto-discover"
  "repo:.config/AutoHotkey/ahk-snippets/js"
  "repo:.config/AutoHotkey/scripts/snippets-local.ahk"
  "repo@under:.config/AutoHotkey/ahk-snippets/passwords"
)

kind_root() {
  case "${1%%@*}" in
    home) printf '%s\n' "$HOME" ;;
    repo) printf '%s\n' "$DOTFILES_DIR" ;;
    *)
      echo "[FAIL] 不明な kind: $1" >&2
      return 1
      ;;
  esac
}

# ディレクトリ直下のうち git が ignore しているものだけを返す。
# 追跡ファイル（README.md 等）を巻き込まないための判定。
ignored_children() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  (
    shopt -s nullglob dotglob
    local c
    for c in "$dir"/*; do
      if git -C "$DOTFILES_DIR" check-ignore -q "$c" 2>/dev/null; then
        basename "$c"
      fi
    done
  )
}

ADOPT_MOVED=0
ADOPT_SKIPPED=0
ADOPT_MISSING=0

adopt_one() {
  local kind="$1" rel="$2" execute="$3"
  local base src dst
  base="$(kind_root "$kind")" || return 1
  src="$base/$rel"
  dst="$PRIVATE_DIR/${kind%%@*}/$rel"

  if [ -L "$src" ]; then
    echo "[SKIP] $rel は既に symlink です"
    ADOPT_SKIPPED=$((ADOPT_SKIPPED + 1))
    return 0
  fi
  if [ ! -e "$src" ]; then
    echo "[MISS] $rel がありません（この端末で使っていなければ問題ありません）"
    ADOPT_MISSING=$((ADOPT_MISSING + 1))
    return 0
  fi
  if [ "$execute" -eq 0 ]; then
    echo "[DRY-RUN] $src を $dst へ移して symlink を張ります"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  if ! mv "$src" "$dst"; then
    echo "[FAIL] $rel の移動に失敗しました" >&2
    return 1
  fi
  ln -sn "$dst" "$src"
  echo "[OK] $rel"
  ADOPT_MOVED=$((ADOPT_MOVED + 1))
}

cmd_adopt() {
  local execute=0
  case "${1:-}" in
    --execute) execute=1 ;;
    "") ;;
    *)
      echo "[FAIL] 不明な引数: $1" >&2
      return 2
      ;;
  esac

  local entry kind rel base child rc=0
  for entry in "${ADOPT_ENTRIES[@]}"; do
    kind="${entry%%:*}"
    rel="${entry#*:}"
    if [ "${kind##*@}" = "under" ]; then
      base="$(kind_root "$kind")" || return 1
      while IFS= read -r child; do
        [ -n "$child" ] || continue
        adopt_one "${kind%%@*}" "$rel/$child" "$execute" || rc=1
      done < <(ignored_children "$base/$rel")
    else
      adopt_one "$kind" "$rel" "$execute" || rc=1
    fi
  done

  echo "---"
  if [ "$execute" -eq 0 ]; then
    echo "dry-run です。実行するには --execute を付けてください"
  else
    echo "移動: $ADOPT_MOVED 件 / 既に symlink: $ADOPT_SKIPPED 件 / 不在: $ADOPT_MISSING 件"
  fi
  return "$rc"
}

usage() {
  sed -n '2,9p' "${BASH_SOURCE[0]}" >&2
}

main() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    adopt) cmd_adopt "$@" ;;
    *)
      usage
      return 2
      ;;
  esac
}

# source されたときは実行しない。テストから関数だけを呼べるようにするため
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
