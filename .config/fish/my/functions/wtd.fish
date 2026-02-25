# git worktree削除（fzfで選択）
# 表示順: branch path commit_hash
function wtd
    set selection (git wt | tail -n +2 | \
        awk '{if ($1 == "*") print "* "$3" "$2" "$4; else print "  "$2" "$1" "$3}' | \
        fzf --ansi --reverse --height=80% \
        --prompt="delete worktree > " \
        --preview 'echo {} | awk "{if (\$1 == \"*\") print \$2; else print \$1}" | xargs -I{} git log --oneline -10 {}')

    if test -z "$selection"
        return 0
    end

    set worktree_path (echo $selection | awk '{if ($1 == "*") print $3; else print $2}')
    echo "削除: $worktree_path"
    git worktree remove "$worktree_path"
end
