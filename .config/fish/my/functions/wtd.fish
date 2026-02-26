# git worktree削除（fzfで選択）
function wtd
    set selection (__wt_select "delete worktree")
    or return 0

    set worktree_path (echo $selection | awk '{if ($1 == "*") print $4; else print $3}')
    echo "削除: $worktree_path"
    git worktree remove "$worktree_path"
end
