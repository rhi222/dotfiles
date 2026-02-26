# git worktree切り替え（git-wtとfzfを使用）
# 参考: https://koic.hatenablog.com/entry/introduce-git-wt
function wt
    set selection (__wt_select worktree)
    or return 0

    set branch (echo $selection | awk '{if ($1 == "*") print $3; else print $2}')
    git wt "$branch"
end
