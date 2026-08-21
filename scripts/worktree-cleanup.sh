#!/bin/bash
#
# worktree-cleanup.sh — dotctl worktree cleanup への互換 wrapper。
#
# 実装は Go 側（internal/worktree）にある。**この入口を残しているのは、
# AGENTS.md・docs・Claude skill・daily-update.sh がこのパスで呼んでいるため。**
# 引数・終了コード・標準出力はそのまま転送する。
#
#   bash scripts/worktree-cleanup.sh            # dry-run（既定）
#   bash scripts/worktree-cleanup.sh --size     # 解放見込みつきで確認
#   bash scripts/worktree-cleanup.sh --execute  # 実削除
#
# 判定表と設計の根拠は docs/worktree.md。
#
# **dotctl の解決規則はここにベタ書きする。** 共通ライブラリに置くと wrapper が
# source に依存し、cron と hook の最小 PATH で「ライブラリが読めない」という
# 新しい失敗点が増える。2行なので重複を許す。
set -uo pipefail

DOTCTL="$HOME/.local/bin/dotctl"
[ -x "$DOTCTL" ] || DOTCTL="$(command -v dotctl 2>/dev/null || true)"

if [ -z "$DOTCTL" ]; then
  echo "worktree-cleanup: dotctl が見つからない。ビルドする: bash scripts/setup-dotctl.sh" >&2
  exit 1
fi

exec "$DOTCTL" worktree cleanup "$@"
