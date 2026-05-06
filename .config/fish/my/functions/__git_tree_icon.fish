# プロンプト用のgit treeアイコン
# プロンプトごとに git rev-parse + realpath を呼ぶと体感が悪いため、PWD単位でキャッシュする。
function __git_tree_icon
    if test "$__git_tree_icon_cache_pwd" = "$PWD"
        echo $__git_tree_icon_cache
        return
    end

    set -l icon
    set -l gitdir (git rev-parse --git-dir 2>/dev/null)
    if test -z "$gitdir"
        set icon "📂"
    else
        set -l real_gitdir (realpath $gitdir)
        if string match -q "*worktrees/*" $real_gitdir
            set icon "🌿"
        else
            set icon "🏠"
        end
    end

    set -g __git_tree_icon_cache_pwd $PWD
    set -g __git_tree_icon_cache $icon
    echo $icon
end
