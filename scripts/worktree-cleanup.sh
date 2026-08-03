#!/bin/bash
#
# worktree-cleanup.sh — 消し忘れた git worktree を洗い出して掃除する。
#
# デフォルトは dry-run（何も削除せず、候補だけ表示）。
# 実際に削除するには --execute を付ける。
#
#   bash scripts/worktree-cleanup.sh            # dry-run（既定）
#   bash scripts/worktree-cleanup.sh --size     # 解放見込みつきで確認
#   bash scripts/worktree-cleanup.sh --execute  # 実削除
#
# 設計方針:
#   - 個別リポジトリの失敗で全体を止めない（set -e は使わない）
#   - locked worktree は必ず残す（Claude セッション実行中の可能性がある）
#   - ローカルブランチは削除しない。worktree ディレクトリだけを消す
#   - worktree の置き場所を決め打ちで走査しない。git worktree list を起点にすることで
#     .wt/ / .claude/worktrees/ / /tmp / 旧 ~/git-worktrees/ をすべて拾う
#
# 注意: set -e は使わない。1つのリポジトリで失敗しても残りを続行したいため。
set -uo pipefail

EXECUTE=0
FORCE=0
SHOW_SIZE=0

# 走査ルート（スペース区切り）。テストから一時ディレクトリを指すために上書きできる。
WORKTREE_CLEANUP_ROOTS="${WORKTREE_CLEANUP_ROOTS:-/data/git-repos}"
# PR状態取得コマンドの差し替え口。テストは gh を叩かずにスタブを渡す。
WORKTREE_CLEANUP_PR_STATE_CMD="${WORKTREE_CLEANUP_PR_STATE_CMD:-}"

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

section() {
  echo
  echo "${C_BOLD}${C_CYAN}== $* ==${C_RESET}"
}

usage() {
  cat <<'EOS'
usage: worktree-cleanup.sh [--execute] [--force] [--size]

  (オプションなし)  dry-run。削除候補を一覧表示する
  --execute         実際に削除する
  --force           未コミット変更・未追跡ファイルがある worktree も削除する
  --size            DELETE 候補のサイズを測って解放見込みを表示する
  -h, --help        この使い方を表示する
EOS
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --execute) EXECUTE=1 ;;
      --force) FORCE=1 ;;
      --size) SHOW_SIZE=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        return 1
        ;;
    esac
    shift
  done
  return 0
}

# パスのサイズをKB単位で返す（存在しない・測定できない場合は 0）。
# 戻り値は必ず10進整数にする。呼び出し側が $(( )) で加算するため、
# 空文字や非数値を返すと算術エラーになる。
path_size_kb() {
  local p="$1" kb
  [ -d "$p" ] || {
    echo 0
    return
  }
  kb=$(du -sk "$p" 2>/dev/null | cut -f1)
  case "$kb" in
    '' | *[!0-9]*) echo 0 ;;
    *) echo "$kb" ;;
  esac
}

# KB を人間可読に整形する。du -sh と同じ単位表記に寄せる。
format_kb() {
  local kb="$1"
  if [ "$kb" -ge 1048576 ]; then
    awk -v k="$kb" 'BEGIN { printf "%.1fG", k / 1048576 }'
  elif [ "$kb" -ge 1024 ]; then
    awk -v k="$kb" 'BEGIN { printf "%dM", k / 1024 }'
  else
    printf '%dK' "$kb"
  fi
}

main() {
  parse_args "$@" || return 1
  return 0
}

# 直接実行のときだけ処理を走らせる。source（test-worktree-cleanup.sh から）では
# 関数定義とデフォルト値の読み込みだけを行う。
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
