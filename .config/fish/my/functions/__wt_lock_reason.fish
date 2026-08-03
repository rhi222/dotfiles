# 指定worktreeのlock理由を返す（lockされていなければreturn 1）
#
# `git worktree list --porcelain` の該当ブロックから `locked` 行を拾う。
# git のエラーメッセージを正規表現で削るより壊れにくい。
function __wt_lock_reason --argument-names worktree_path
    test -n "$worktree_path"; or return 1

    set -l reason (git worktree list --porcelain | awk -v target="$worktree_path" '
        $1 == "worktree" { cur = substr($0, 10); next }
        cur == target && $1 == "locked" { print substr($0, 8); found = 1; exit }
        END { exit(found ? 0 : 1) }
    ')
    or return 1

    # 理由なしでlockされている場合は空文字を返す（statusは0）
    printf '%s\n' "$reason"
end
