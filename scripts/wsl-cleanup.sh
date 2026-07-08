#!/bin/bash
#
# WSL2 開発環境のキャッシュ・不要ファイルを安全に掃除するスクリプト。
#
# デフォルトは dry-run（何も削除せず、対象とサイズだけ表示）。
# 実際に削除するには --execute を付ける。
#
#   bash scripts/wsl-cleanup.sh            # dry-run（既定）
#   bash scripts/wsl-cleanup.sh --execute  # 実削除
#
# 設計方針:
#   - 個別コマンドが失敗しても全体は止めない（set -e は使わない）
#   - コマンドが無い／対象が無い場合はスキップ
#   - .cargo / .rustup / ~/go / mise / nvim / claude など開発環境本体は触らない
#   - ext4.vhdx の圧縮は Windows 側で手動。最後に手順を案内するだけ。
#
# 注意: set -e は使わない。1つの掃除が失敗しても残りを続行したいため。
set -uo pipefail

# ---- 引数パース --------------------------------------------------------------
EXECUTE=0
for arg in "$@"; do
  case "$arg" in
    --execute) EXECUTE=1 ;;
    -h | --help)
      grep '^#' "$0" | sed 's/^#//; s/^ //' | head -n 20
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: bash $0 [--execute]" >&2
      exit 1
      ;;
  esac
done

# ---- 表示ヘルパー ------------------------------------------------------------
if [ -t 1 ]; then
  C_BOLD=$'\e[1m'
  C_GREEN=$'\e[32m'
  C_YELLOW=$'\e[33m'
  C_CYAN=$'\e[36m'
  C_RESET=$'\e[0m'
else
  C_BOLD=""
  C_GREEN=""
  C_YELLOW=""
  C_CYAN=""
  C_RESET=""
fi

if [ "$EXECUTE" -eq 1 ]; then
  MODE="${C_GREEN}EXECUTE（実削除）${C_RESET}"
else
  MODE="${C_YELLOW}DRY-RUN（試走／削除しません）${C_RESET}"
fi

freed_total_human=()

section() {
  echo
  echo "${C_BOLD}${C_CYAN}== $* ==${C_RESET}"
}

# パスのサイズを人間可読で返す（存在しなければ空）。
path_size() {
  local p="$1"
  [ -e "$p" ] || {
    echo ""
    return
  }
  du -sh "$p" 2>/dev/null | cut -f1
}

# 指定パスを掃除する。dry-run ならサイズ表示のみ。
#   clean_path <ラベル> <パス>
clean_path() {
  local label="$1" path="$2"
  if [ ! -e "$path" ]; then
    echo "  [skip] $label: 見つかりません ($path)"
    return
  fi
  local size
  size="$(path_size "$path")"
  echo "  $label: ${C_BOLD}${size:-?}${C_RESET}  ($path)"
  if [ "$EXECUTE" -eq 1 ]; then
    if rm -rf -- "$path"; then
      echo "    ${C_GREEN}削除しました${C_RESET}（約 ${size:-?} 解放）"
      freed_total_human+=("$label: ${size:-?}")
    else
      echo "    ${C_YELLOW}削除に失敗しました（権限/ロック?）${C_RESET}" >&2
    fi
  else
    echo "    ${C_YELLOW}(dry-run: 削除しません)${C_RESET}"
  fi
}

# コマンド経由の掃除。dry-run なら対象キャッシュ dir のサイズだけ見せる。
#   clean_cmd <ラベル> <存在確認するコマンド> <表示用キャッシュパス(任意)> -- <実行コマンド...>
clean_cmd() {
  local label="$1" bin="$2" cache_hint="$3"
  shift 3
  [ "$1" = "--" ] && shift

  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "  [skip] $label: '$bin' コマンドが無いためスキップ"
    return
  fi

  if [ -n "$cache_hint" ] && [ -e "$cache_hint" ]; then
    echo "  $label: ${C_BOLD}$(path_size "$cache_hint")${C_RESET}  ($cache_hint)"
  else
    echo "  $label: (サイズ未測定 / コマンド内部で処理)"
  fi

  if [ "$EXECUTE" -eq 1 ]; then
    if "$@" >/dev/null 2>&1; then
      echo "    ${C_GREEN}実行しました${C_RESET}: $*"
    else
      echo "    ${C_YELLOW}実行に失敗しました${C_RESET}: $*" >&2
    fi
  else
    echo "    ${C_YELLOW}(dry-run: 実行しません)${C_RESET}  → $*"
  fi
}

# ---- 開始 -------------------------------------------------------------------
echo "${C_BOLD}WSL2 cleanup${C_RESET}  mode: $MODE"
echo "実行前の全体サイズ:"
echo "  ~        : $(du -sh "$HOME" 2>/dev/null | cut -f1)"
echo "  ~/.cache : $(path_size "$HOME/.cache")"

# ---- パッケージマネージャ系キャッシュ ---------------------------------------
section "パッケージマネージャ キャッシュ"
clean_cmd "npm cache" npm "$HOME/.npm" -- npm cache clean --force
clean_cmd "uv cache" uv "$HOME/.cache/uv" -- uv cache clean
clean_cmd "pip cache" pip "$HOME/.cache/pip" -- pip cache purge

# ---- ブラウザ自動化 / ビルド系キャッシュ ------------------------------------
section "ブラウザ自動化・ビルドキャッシュ"
clean_path "puppeteer cache" "$HOME/.cache/puppeteer"
clean_path "playwright cache" "$HOME/.cache/ms-playwright"
clean_path "node-gyp cache" "$HOME/.cache/node-gyp"
clean_path "pnpm cache" "$HOME/.cache/pnpm"

# ---- 未使用 pnpm store --------------------------------------------------------
# `pnpm store path` が指す現行 store 以外の store/v* を削除する。
# 現行 store は中身が使われているため絶対に消さない。
section "未使用 pnpm store (store/v*)"
PNPM_STORE_ROOT="$HOME/.local/share/pnpm/store"
if ! command -v pnpm >/dev/null 2>&1; then
  echo "  [skip] pnpm コマンドが無いためスキップ"
elif [ ! -d "$PNPM_STORE_ROOT" ]; then
  echo "  [skip] store ディレクトリが見つかりません ($PNPM_STORE_ROOT)"
else
  # 現行 store のパスを取得。store path は <root>/v3 のような末尾を持つ。
  CURRENT_STORE="$(pnpm store path 2>/dev/null)"
  echo "  現行 store: ${C_GREEN}${CURRENT_STORE:-取得失敗}${C_RESET}"
  # 比較を堅牢にするため正規化（末尾スラッシュ除去 + realpath 解決）。
  norm() {
    local p="$1"
    p="${p%/}"
    realpath -m -- "$p" 2>/dev/null || echo "$p"
  }
  CURRENT_NORM="$(norm "$CURRENT_STORE")"

  shopt -s nullglob
  for store in "$PNPM_STORE_ROOT"/v*; do
    [ -d "$store" ] || continue
    if [ "$(norm "$store")" = "$CURRENT_NORM" ]; then
      echo "  [keep] $(basename "$store"): 現行 store のため保持  ($(path_size "$store"))"
    else
      clean_path "未使用 store $(basename "$store")" "$store"
    fi
  done
  shopt -u nullglob
fi

# ---- 実行後サマリ -----------------------------------------------------------
section "実行後のサイズ"
echo "  du -sh ~                      → $(du -sh "$HOME" 2>/dev/null | cut -f1)"
echo "  du -sh ~/.cache               → $(path_size "$HOME/.cache" || echo "-")"
echo "  du -sh ~/.local/share/pnpm    → $(path_size "$HOME/.local/share/pnpm" || echo "-")"
echo "  df -h /:"
df -h / | sed 's/^/    /'

if [ "$EXECUTE" -eq 1 ] && [ "${#freed_total_human[@]}" -gt 0 ]; then
  section "削除した項目"
  for item in "${freed_total_human[@]}"; do
    echo "  - $item"
  done
fi

# ---- VHDX 圧縮の案内 --------------------------------------------------------
section "次のステップ: ext4.vhdx の圧縮（Windows 側で手動）"
cat <<'EOS'
  WSL2 のディスクイメージ (ext4.vhdx) は、中で削除しても自動では縮みません。
  実ディスクの空きを取り戻すには Windows 側で圧縮します。

  1. PowerShell を「管理者として実行」で開く
  2. WSL を停止:
       wsl --shutdown
  3. diskpart を起動して圧縮:
       diskpart
       select vdisk file="C:\Users\<ユーザー名>\AppData\Local\Packages\<ディストロのパッケージ名>\LocalState\ext4.vhdx"
       attach vdisk readonly
       compact vdisk
       detach vdisk
       exit

  ※ vhdx の場所が不明な場合（PowerShell）:
       (Get-ChildItem -Path $env:LOCALAPPDATA\Packages -Recurse -Filter ext4.vhdx -ErrorAction SilentlyContinue).FullName
EOS

if [ "$EXECUTE" -ne 1 ]; then
  echo
  echo "${C_YELLOW}これは dry-run です。実際に削除するには --execute を付けて再実行してください。${C_RESET}"
fi
