#!/usr/bin/env bash
# worktree-init.sh — git worktree作成後の初期化
#
# 1. メインworktreeから gitignore対象の .env* ファイルを相対パスを保ってコピー
#    （既存ファイルは上書きしない。node_modules / .wt 配下は対象外）
# 2. lockファイルを判定して依存をインストール（pnpm / npm / yarn）
#
# 使い方: worktree-init.sh [--dry-run] [worktree-path]
#   worktree-path 省略時はカレントディレクトリ。
#   git-wt の wt.hook からは新worktreeがカレントの状態で引数なしで呼ばれる。
set -euo pipefail

DRY_RUN=0
TARGET=""

usage() {
  echo "usage: worktree-init.sh [--dry-run] [worktree-path]"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "error: 不明なオプション: $1" >&2
      usage >&2
      exit 1
      ;;
    *) TARGET="$1" ;;
  esac
  shift
done

TARGET="${TARGET:-$PWD}"

if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: gitリポジトリ内ではありません: $TARGET" >&2
  exit 1
fi

git_dir=$(git -C "$TARGET" rev-parse --path-format=absolute --git-dir)
common_dir=$(git -C "$TARGET" rev-parse --path-format=absolute --git-common-dir)

if [ "$git_dir" = "$common_dir" ]; then
  echo "error: メインworktreeです。linked worktree内で実行してください: $TARGET" >&2
  exit 1
fi

# common_dir は <メインworktree>/.git を指す
main_worktree=$(dirname "$common_dir")
if [ ! -e "$main_worktree/.git" ]; then
  echo "error: メインworktreeを特定できません（bare repository?）" >&2
  exit 1
fi

# メインworktree内の gitignore対象 .env* をコピーする
copy_env_files() {
  local rel
  while IFS= read -r rel; do
    rel="${rel#./}"
    # trackedファイル（.env.example 等）は check-ignore に該当せず除外される
    git -C "$main_worktree" check-ignore -q "$rel" || continue
    if [ -e "$TARGET/$rel" ]; then
      echo "skip (既存): $rel"
    elif [ "$DRY_RUN" = 1 ]; then
      echo "[dry-run] copy: $rel"
    else
      mkdir -p "$TARGET/$(dirname "$rel")"
      cp -p "$main_worktree/$rel" "$TARGET/$rel"
      echo "copy: $rel"
    fi
  done < <(cd "$main_worktree" && find . \( -name node_modules -o -name .wt -o -name .git \) -prune -o -type f -name '.env*' -print)
}

# lockファイルから依存インストールコマンドを判定して実行する
install_deps() {
  local cmd=""
  if [ -f "$TARGET/pnpm-lock.yaml" ]; then
    cmd="pnpm install"
  elif [ -f "$TARGET/package-lock.json" ]; then
    cmd="npm ci"
  elif [ -f "$TARGET/yarn.lock" ]; then
    cmd="yarn install"
  fi

  if [ -z "$cmd" ]; then
    echo "install: skip（lockファイルなし）"
  elif [ "$DRY_RUN" = 1 ]; then
    echo "[dry-run] install: $cmd"
  else
    echo "install: $cmd"
    (cd "$TARGET" && $cmd)
  fi
}

copy_env_files
install_deps
