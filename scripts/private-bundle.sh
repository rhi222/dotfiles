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
    # 集約先は資格情報を1箇所に集めたディレクトリなので、作った直後に締める。
    # import 側だけでハードニングすると、集約した端末では 755 のまま残る。
    [ -d "$PRIVATE_DIR" ] && harden_permissions
    echo "移動: $ADOPT_MOVED 件 / 既に symlink: $ADOPT_SKIPPED 件 / 不在: $ADOPT_MISSING 件"
  fi
  return "$rc"
}

# 相対パスのままだと cd 後に別の場所を指すので絶対パスへ直す
abspath() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$PWD/$1" ;;
  esac
}

# zip の暗号化引数。テストからは PRIVATE_BUNDLE_ZIP_PASSWORD で対話プロンプトを
# 迂回する（-P は平文が ps に乗るので実運用では使わない）
zip_crypt_args() {
  if [ -n "${PRIVATE_BUNDLE_ZIP_PASSWORD:-}" ]; then
    printf '%s\n%s\n' "-P" "$PRIVATE_BUNDLE_ZIP_PASSWORD"
  else
    printf '%s\n' "-e"
  fi
}

cmd_export() {
  local out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --out)
        out="${2:-}"
        shift 2 || return 2
        ;;
      *)
        echo "[FAIL] 不明な引数: $1" >&2
        return 2
        ;;
    esac
  done

  if [ ! -d "$PRIVATE_DIR" ]; then
    echo "[FAIL] 集約先がありません: $PRIVATE_DIR" >&2
    echo "       先に adopt --execute を実行してください" >&2
    return 1
  fi

  out="$(abspath "${out:-$HOME/dotfiles-private-$(date +%Y%m%d).zip}")"
  if [ -e "$out" ]; then
    echo "[FAIL] 既に存在します: $out" >&2
    return 1
  fi

  local crypt=()
  mapfile -t crypt < <(zip_crypt_args)

  # -y は必須。無いと集約先の symlink を辿って実体化し、repos.yml が2つになる
  if ! (cd "$PRIVATE_DIR" && zip -r -y -q "${crypt[@]}" "$out" . \
    -x '*.DS_Store' '*~' '*.swp'); then
    echo "[FAIL] zip の作成に失敗しました" >&2
    rm -f "$out"
    return 1
  fi
  chmod 600 "$out"
  echo "[OK] $out"
  echo "     新環境で: bash scripts/private-bundle.sh import <このzip>"
}

# パーミッションは zip の保存内容に頼らず張り直す。Windows 側で開いて
# 再圧縮すると Unix 属性が落ち、api-key が 644 で復元されるため。
# -type f/d は symlink を辿らないので symlink 自体は触らない。
harden_permissions() {
  chmod 700 "$PRIVATE_DIR"
  find "$PRIVATE_DIR" -type d -exec chmod 700 {} +
  find "$PRIVATE_DIR" -type f -exec chmod 600 {} +
}

cmd_import() {
  local zipfile="${1:-}" force=0
  shift || true
  case "${1:-}" in
    --force) force=1 ;;
    "") ;;
    *)
      echo "[FAIL] 不明な引数: $1" >&2
      return 2
      ;;
  esac

  if [ ! -f "$zipfile" ]; then
    echo "[FAIL] zip がありません: $zipfile" >&2
    return 1
  fi
  if [ -e "$PRIVATE_DIR" ] && [ "$force" -eq 0 ]; then
    echo "[FAIL] 集約先が既に存在します: $PRIVATE_DIR" >&2
    echo "       上書きしてよければ --force を付けてください" >&2
    return 1
  fi

  local crypt=()
  mapfile -t crypt < <(zip_crypt_args)
  # unzip の暗号化オプションは -P だけ。-e は zip 側の対話指定なので落とす
  [ "${crypt[0]}" = "-e" ] && crypt=()

  mkdir -p "$PRIVATE_DIR"
  if ! unzip -q -o "${crypt[@]}" "$zipfile" -d "$PRIVATE_DIR"; then
    echo "[FAIL] 展開に失敗しました（パスワードを確認してください）" >&2
    return 1
  fi
  harden_permissions
  echo "[OK] $PRIVATE_DIR に展開しました"
  echo "     次に ./dotfilesLink.sh を実行してください"
}

STATUS_LINKED=()
STATUS_UNLINKED=()
STATUS_BROKEN=()
STATUS_ABSENT=()

# 集約先の直下の名前を1行ずつ返す（ignore 判定を通さない版）
bundle_children() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  (
    shopt -s nullglob dotglob
    local c
    for c in "$dir"/*; do
      basename "$c"
    done
  )
}

# リンク切れを最初に見る。実体が消えたうえに dangling symlink が残っている状態は
# 「集約先に無い」にも当てはまるが、手を打つ必要があるのはリンク切れのほうなので、
# そちらへ寄せる。
status_classify() {
  local kind="$1" rel="$2" base src dst
  base="$(kind_root "$kind")" || return 1
  src="$base/$rel"
  dst="$PRIVATE_DIR/${kind%%@*}/$rel"

  if [ -L "$src" ] && [ ! -e "$src" ]; then
    STATUS_BROKEN+=("$src")
  elif [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    STATUS_ABSENT+=("${kind%%@*}/$rel")
  elif [ -L "$src" ]; then
    STATUS_LINKED+=("$src")
  else
    STATUS_UNLINKED+=("$src")
  fi
}

status_print_group() {
  local label="$1" hint="$2"
  shift 2
  if [ -n "$hint" ]; then
    echo "$label ($#)  ← $hint"
  else
    echo "$label ($#)"
  fi
  local item
  for item in "$@"; do
    echo "  $item"
  done
  echo ""
}

# 宣言（ADOPT_ENTRIES）を基準に判定する。集約先の走査だけだと
# 「集約先に無い＝旧環境からのコピーがまだ」を検出できないため。
cmd_status() {
  if [ ! -d "$PRIVATE_DIR" ]; then
    echo "集約先がありません: $PRIVATE_DIR"
    echo "  旧環境があるなら: bash scripts/private-bundle.sh import <zip>"
    echo "  無いなら雛形生成にフォールバックします（./dotfilesLink.sh）"
    return 0
  fi

  echo "集約先: $PRIVATE_DIR"
  echo ""

  local entry kind rel base child
  for entry in "${ADOPT_ENTRIES[@]}"; do
    kind="${entry%%:*}"
    rel="${entry#*:}"
    if [ "${kind##*@}" = "under" ]; then
      base="$(kind_root "$kind")" || return 1
      # 集約先とリポジトリ側の両方から子を集める（片方にしか無い状態も出したい）
      while IFS= read -r child; do
        [ -n "$child" ] || continue
        status_classify "${kind%%@*}" "$rel/$child"
      done < <(
        {
          ignored_children "$base/$rel"
          bundle_children "$PRIVATE_DIR/${kind%%@*}/$rel"
        } | sort -u
      )
    else
      status_classify "$kind" "$rel"
    fi
  done

  status_print_group "リンク済み" "" "${STATUS_LINKED[@]}"
  status_print_group "未リンク" "./dotfilesLink.sh を実行してください" "${STATUS_UNLINKED[@]}"
  status_print_group "リンク切れ" "集約先から実体が消えています" "${STATUS_BROKEN[@]}"
  status_print_group "集約先に無い" "旧環境からのコピーか手書きが必要" "${STATUS_ABSENT[@]}"
}

usage() {
  sed -n '2,9p' "${BASH_SOURCE[0]}" >&2
}

main() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    adopt) cmd_adopt "$@" ;;
    export) cmd_export "$@" ;;
    import) cmd_import "$@" ;;
    status) cmd_status "$@" ;;
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
