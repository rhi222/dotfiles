#!/usr/bin/env bash
# worktree-init.sh — dotctl worktree init への互換 wrapper。
#
# 実装は Go 側（internal/worktree）にある。**この入口を残しているのは、
# git-wt の wt.hook・dotfilesLink.sh・docs がこのパスで呼んでいるため。**
# 引数・終了コード・標準出力はそのまま転送する。
#
# 使い方: worktree-init.sh [--dry-run] [worktree-path]
#   worktree-path 省略時はカレントディレクトリ。
#   git-wt の wt.hook からは新 worktree がカレントの状態で引数なしで呼ばれる。
#
# リポジトリ固有の初期化の差し込み方は docs/worktree.md。
#
# **dotctl の解決規則はここにベタ書きする。** 共通ライブラリに置くと wrapper が
# source に依存し、hook の最小 PATH で「ライブラリが読めない」という新しい
# 失敗点が増える。
set -uo pipefail

DOTCTL="$HOME/.local/bin/dotctl"
[ -x "$DOTCTL" ] || DOTCTL="$(command -v dotctl 2>/dev/null || true)"

if [ -z "$DOTCTL" ]; then
  echo "worktree-init: dotctl が見つからない。ビルドする: bash scripts/setup/dotctl.sh" >&2
  exit 1
fi

exec "$DOTCTL" worktree init "$@"
