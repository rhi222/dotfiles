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

# ---- 走査 -------------------------------------------------------------------
# パスを比較可能な形に正規化する。
norm_path() {
  local p="${1%/}"
  realpath -m -- "$p" 2>/dev/null || printf '%s' "$p"
}

# 走査ルート配下のgitリポジトリ（非bare）を列挙する。
discover_repos() {
  local root git_dir
  for root in $WORKTREE_CLEANUP_ROOTS; do
    [ -d "$root" ] || continue
    while IFS= read -r git_dir; do
      [ -n "$git_dir" ] || continue
      norm_path "$(dirname "$git_dir")"
    done < <(find "$root" -maxdepth 4 -type d -name .git -prune 2>/dev/null)
  done
}

# main worktree の正規化済みパスを返す。
# git-common-dir は <メインworktree>/.git を指すので、その親がmain worktree。
# レコード順（gitはmainを先頭に出す）に依存しないためにこの方法を使う。
main_worktree_path() {
  local repo="$1" common_dir
  common_dir=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  norm_path "$(dirname "$common_dir")"
}

# linked worktree を TSV で列挙する。
#   path <TAB> branch <TAB> flags <TAB> detail
# branch は detached のとき空文字。flags は locked/prunable のカンマ区切り（無ければ -）。
list_worktrees() {
  local repo="$1"
  local main_path porcelain
  main_path=$(main_worktree_path "$repo") || return 1
  porcelain=$(git -C "$repo" worktree list --porcelain 2>/dev/null) || return 1

  local path="" branch="" flags="" detail="" out_flags="" line
  # porcelain は各レコードの後に空行を置き、末尾も空行で終わる（git 2.54.0 で実測）。
  # よって空行を見たタイミングでレコードを1件確定できる。
  # ただし $(...) は末尾の改行を全て落とすので、最後のレコードを確定させるために
  # herestring 側で空行を1つ補う（$'\n'）。
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch refs/heads/"*) branch="${line#branch refs/heads/}" ;;
      "locked")
        flags="$flags,locked"
        ;;
      "locked "*)
        flags="$flags,locked"
        detail="${line#locked }"
        ;;
      "prunable")
        flags="$flags,prunable"
        ;;
      "prunable "*)
        flags="$flags,prunable"
        detail="${line#prunable }"
        ;;
      "")
        # main worktree は除外する。flags が空なら "-" を出す。
        if [ -n "$path" ] && [ "$(norm_path "$path")" != "$main_path" ]; then
          out_flags="-"
          [ -n "$flags" ] && out_flags="${flags#,}"
          printf '%s\t%s\t%s\t%s\n' "$path" "$branch" "$out_flags" "$detail"
        fi
        path=""
        branch=""
        flags=""
        detail=""
        ;;
    esac
  done <<<"$porcelain"$'\n'
}

# ---- PR状態 ------------------------------------------------------------------
# ブランチに対応するPRの状態を取得する。
#   stdout: "MERGED #10737" / "CLOSED #99" / "OPEN #11068" / "NONE"
#   return: 取得できなければ非ゼロ（未認証・権限不足・ネットワーク断など）
#
# 同一ブランチ名に複数PRがある場合は gh の既定順（作成日時の降順）の先頭を採る。
get_pr_state() {
  local repo="$1" branch="$2"

  # テストや手元検証用の差し替え口
  if [ -n "$WORKTREE_CLEANUP_PR_STATE_CMD" ]; then
    "$WORKTREE_CLEANUP_PR_STATE_CMD" "$repo" "$branch"
    return $?
  fi

  command -v gh >/dev/null 2>&1 || return 1

  local out
  # リポジトリを cd で与えることで owner/repo の導出を gh に任せる。
  out=$( (cd "$repo" && gh pr list \
    --head "$branch" \
    --state all \
    --json number,state \
    --limit 1 \
    --jq 'if length == 0 then "NONE" else (.[0].state + " #" + (.[0].number | tostring)) end') 2>/dev/null) || return 1

  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
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
