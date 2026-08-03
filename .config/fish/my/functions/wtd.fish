# git worktree削除（fzfで選択）
# -f/--force: 未コミット・未追跡ファイルがあっても削除する
#             2回指定（-ff）でlock済みworktreeも削除する
function wtd
    argparse h/help 'f/force' -- $argv
    or return 1

    if set -q _flag_help
        echo "使い方: wtd [-f|--force]"
        echo "  -f, --force   未コミット変更があっても削除（-ff でlock済みも削除）"
        return 0
    end

    set selection (__wt_select "delete worktree")
    or return 0

    set worktree_path (echo $selection | awk '{if ($1 == "*") print $4; else print $3}')

    set -l force_args
    for i in (seq (count $_flag_force))
        set -a force_args --force
    end

    echo "削除: $worktree_path"
    git worktree remove $force_args "$worktree_path"
end
