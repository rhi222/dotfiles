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

# 集計（process_repo が更新する）
N_DELETE=0
N_PRUNE=0
N_SKIP=0
N_KEEP=0
N_SKIP_LOCKED=0
N_SKIP_DETACHED=0
N_SKIP_DIRTY=0
FREED_KB=0
DELETE_PATHS=()
PRUNE_REPOS=()

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
  --force           追跡ファイルに未コミット変更がある worktree も削除する
                    （未追跡ファイルのみの場合は --force なしでも削除対象になり、
                     理由文に「未追跡 N 件あり」と件数を併記する）
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

# ---- 判定 -------------------------------------------------------------------
# 追跡ファイルに未コミット変更があるか。あれば 0、なければ 1 を返す。
# 未追跡ファイルは意図的に見ない（--untracked-files=no）。
# 理由: dirty の実体が plans/ 等の使い捨てスクラッチ1件であることが多く、
# 未追跡を dirty に含めるとマージ済みworktreeの削除がほぼ全部ブロックされる。
has_tracked_changes() {
  local path="$1"
  [ -n "$(git -C "$path" status --porcelain --untracked-files=no 2>/dev/null)" ]
}

# 未追跡ファイルの件数を10進整数で返す（測定できなければ 0）。
# 呼び出し側が $(( )) や比較で使うため、必ず数値を返す。
count_untracked() {
  local path="$1" n
  n=$(git -C "$path" status --porcelain --untracked-files=normal 2>/dev/null | grep -c '^??')
  case "$n" in
    '' | *[!0-9]*) echo 0 ;;
    *) echo "$n" ;;
  esac
}

# worktree を KEEP / DELETE / SKIP / PRUNE に分類する。
#   stdout: "<verdict>\t<reason>"
#
# 上から順に評価し、最初にマッチした時点で確定する。順序には意味がある:
#   locked を最優先にしないと、実行中のClaudeセッションの作業ディレクトリを消しうる。
classify_worktree() {
  local repo="$1" path="$2" branch="$3" flags="$4" detail="$5"

  # 1. locked: Claudeセッション実行中の可能性があるため必ず残す
  case ",$flags," in
    *,locked,*)
      printf 'SKIP\tlocked (%s)\n' "${detail:-理由未設定}"
      return 0
      ;;
  esac

  # 2. prunable: ディレクトリが既に無い。削除ではなく prune の対象
  case ",$flags," in
    *,prunable,*)
      printf 'PRUNE\tディレクトリ消失 (%s)\n' "${detail:-理由未設定}"
      return 0
      ;;
  esac

  # 3. detached HEAD: ブランチが無くPR判定ができない
  if [ -z "$branch" ]; then
    printf 'SKIP\tdetached HEAD（PR判定不能）\n'
    return 0
  fi

  # 4. 追跡ファイルの未コミット変更: 作業中の可能性。--force で解除できる
  #    未追跡ファイルのみの場合はここで止めず、ルール5で件数を併記して削除候補にする
  if [ "$FORCE" -eq 0 ] && has_tracked_changes "$path"; then
    printf 'SKIP\t未コミット変更あり（--force で削除対象に含める）\n'
    return 0
  fi

  # 5-6. PR状態で判定
  local pr
  if ! pr=$(get_pr_state "$repo" "$branch"); then
    printf 'KEEP\tPR状態の取得に失敗\n'
    return 0
  fi

  case "$pr" in
    MERGED* | CLOSED*)
      local untracked
      untracked=$(count_untracked "$path")
      if [ "$untracked" -gt 0 ]; then
        printf 'DELETE\t%s（未追跡 %s 件あり）\n' "$pr" "$untracked"
      else
        printf 'DELETE\t%s\n' "$pr"
      fi
      ;;
    NONE)
      printf 'KEEP\tPR なし\n'
      ;;
    *)
      printf 'KEEP\t%s\n' "$pr"
      ;;
  esac
  return 0
}

# ---- レポート ----------------------------------------------------------------
# 1リポジトリを処理してセクションを表示し、集計を更新する。
process_repo() {
  local repo="$1"
  local wt_lines
  wt_lines=$(list_worktrees "$repo") || {
    echo "  [warn] worktree一覧の取得に失敗: $repo" >&2
    return 0
  }
  # linked worktree が無いリポジトリはセクションごと出さない（出力を静かに保つ）
  [ -n "$wt_lines" ] || return 0

  section "$repo"

  local path branch flags detail verdict reason line cw_out
  local has_prunable=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # TAB は IFS の空白文字なので `IFS=$'\t' read` だと連続タブが1つに畳まれ、
    # detached worktree の空 branch フィールドが消えて以降が1つずれる。
    # 空フィールドを保持するためタブ区切りを手動で分解する。
    path="${line%%$'\t'*}"
    line="${line#*$'\t'}"
    branch="${line%%$'\t'*}"
    line="${line#*$'\t'}"
    flags="${line%%$'\t'*}"
    detail="${line#*$'\t'}"
    [ -n "$path" ] || continue

    # classify_worktree の出力も同じ理由で手動分解する（verdict/reason は空にならないが方法を揃える）。
    cw_out=$(classify_worktree "$repo" "$path" "$branch" "$flags" "$detail")
    verdict="${cw_out%%$'\t'*}"
    reason="${cw_out#*$'\t'}"

    local label="${branch:-（detached）}"
    local size_note=""

    case "$verdict" in
      DELETE)
        N_DELETE=$((N_DELETE + 1))
        # 削除時に git -C <repo> を使うため、リポジトリとworktreeパスの組で持つ
        DELETE_PATHS+=("$repo"$'\t'"$path")
        if [ "$SHOW_SIZE" -eq 1 ]; then
          local kb
          kb=$(path_size_kb "$path")
          FREED_KB=$((FREED_KB + kb))
          size_note="  $(format_kb "$kb")"
        fi
        printf '  %s[DELETE]%s %-44s %s%s\n' "$C_GREEN" "$C_RESET" "$label" "$reason" "$size_note"
        ;;
      PRUNE)
        N_PRUNE=$((N_PRUNE + 1))
        has_prunable=1
        printf '  %s[PRUNE ]%s %-44s %s\n' "$C_CYAN" "$C_RESET" "$label" "$reason"
        ;;
      SKIP)
        N_SKIP=$((N_SKIP + 1))
        case "$reason" in
          locked*) N_SKIP_LOCKED=$((N_SKIP_LOCKED + 1)) ;;
          detached*) N_SKIP_DETACHED=$((N_SKIP_DETACHED + 1)) ;;
          *) N_SKIP_DIRTY=$((N_SKIP_DIRTY + 1)) ;;
        esac
        printf '  %s[SKIP  ]%s %-44s %s\n' "$C_YELLOW" "$C_RESET" "$label" "$reason"
        ;;
      *)
        N_KEEP=$((N_KEEP + 1))
        printf '  [KEEP  ] %-44s %s\n' "$label" "$reason"
        ;;
    esac
  done <<<"$wt_lines"

  [ "$has_prunable" -eq 1 ] && PRUNE_REPOS+=("$repo")
  return 0
}

print_summary() {
  section "サマリ"
  echo "  DELETE 候補: $N_DELETE 件"
  echo "  PRUNE  対象: $N_PRUNE 件"
  echo "  SKIP       : $N_SKIP 件 (locked $N_SKIP_LOCKED / detached $N_SKIP_DETACHED / 未コミット変更 $N_SKIP_DIRTY)"
  echo "  KEEP       : $N_KEEP 件"
  if [ "$SHOW_SIZE" -eq 1 ]; then
    echo "  解放見込み : $(format_kb "$FREED_KB")"
  fi
  # 機械可読サマリ行。daily-update.sh はこの行から件数を取る（表示行はgrepしない）。
  echo "worktree-cleanup: DELETE_CANDIDATES=$N_DELETE PRUNE=$N_PRUNE SKIP=$N_SKIP KEEP=$N_KEEP"
}

# ---- 実行 -------------------------------------------------------------------
# DELETE候補を削除し、prunable を掃除する。個別の失敗では止まらない。
execute_deletions() {
  local entry del_repo del_path repo
  local force_args=()

  # スクリプトの --force は git へも伝播させる。dirty な worktree の remove は
  # --force なしでは git 自身が exit 128 で拒否するため（git 2.54.0 で実測）。
  [ "$FORCE" -eq 1 ] && force_args=(--force)

  if [ "${#DELETE_PATHS[@]}" -gt 0 ]; then
    section "削除の実行"
    for entry in "${DELETE_PATHS[@]}"; do
      # `IFS=$'\t' read` は使わない。TAB は IFS の空白文字なので連続タブが1区切りに
      # 畳まれ、空フィールドが消えてフィールドがずれる（Task 5 で実際にこのバグを踏んだ）。
      # ここは repo/path とも非空なので実害は出ないが、同じ脆いパターンを再導入しない
      # ため process_repo と同じ手動分解に揃える。
      del_repo="${entry%%$'\t'*}"
      del_path="${entry#*$'\t'}"
      # git -C はリポジトリ側を指す。削除対象の worktree 内を指すと cwd が消える。
      if git -C "$del_repo" worktree remove "${force_args[@]}" "$del_path" 2>/dev/null; then
        echo "  ${C_GREEN}削除${C_RESET}: $del_path"
      else
        echo "  ${C_YELLOW}削除に失敗（継続します）${C_RESET}: $del_path" >&2
      fi
    done
  fi

  if [ "${#PRUNE_REPOS[@]}" -gt 0 ]; then
    section "prune の実行"
    for repo in "${PRUNE_REPOS[@]}"; do
      git -C "$repo" worktree prune -v 2>&1 | sed 's/^/  /' ||
        echo "  ${C_YELLOW}prune に失敗（継続します）${C_RESET}: $repo" >&2
    done
  fi
}

main() {
  parse_args "$@" || return 1

  local mode
  if [ "$EXECUTE" -eq 1 ]; then
    mode="${C_GREEN}EXECUTE（実削除）${C_RESET}"
  else
    mode="${C_YELLOW}DRY-RUN（試走／削除しません）${C_RESET}"
  fi
  echo "${C_BOLD}worktree cleanup${C_RESET}  mode: $mode"
  echo "走査ルート: $WORKTREE_CLEANUP_ROOTS"

  local repo
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    process_repo "$repo"
  done < <(discover_repos)

  if [ "$EXECUTE" -eq 1 ]; then
    execute_deletions
  fi

  print_summary

  if [ "$EXECUTE" -ne 1 ]; then
    echo
    echo "${C_YELLOW}これは dry-run です。実際に削除するには --execute を付けて再実行してください。${C_RESET}"
  fi
  return 0
}

# 直接実行のときだけ処理を走らせる。source（test-worktree-cleanup.sh から）では
# 関数定義とデフォルト値の読み込みだけを行う。
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
