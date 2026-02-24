# git worktree切り替え（git-wtとfzfを使用）
# 参考: https://koic.hatenablog.com/entry/introduce-git-wt
function wt
    set selection (git wt | tail -n +2 | fzf --ansi --reverse --height=80% \
        --prompt="worktree > " \
        --preview 'echo {} | awk "{print \$1}" | xargs -I{} git log --oneline -10 {}')

    if test -z "$selection"
        return 0
    end

    set branch (echo $selection | awk '{print $(NF-1)}')
    git wt "$branch"
end
