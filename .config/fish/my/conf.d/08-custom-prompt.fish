# Custom prompt settings (extends tide)
# Add git tree icon to tide prompt

function __git_tree_icon
    set -l gitdir (git rev-parse --git-dir 2>/dev/null)
    if test -z "$gitdir"
        echo "📂" # Git 管理外
        return
    end

    set -l real_gitdir (realpath $gitdir)
    if string match -q "*worktrees/*" $real_gitdir
        echo "🌿" # worktree 内
    else
        echo "🏠" # メインリポ
    end
end

# Save original tide prompt before overriding
if functions -q fish_prompt
    functions -c fish_prompt _original_tide_prompt
end

# Wrap tide's prompt to add git tree icon
function fish_prompt
    # Prepend git tree icon
    set_color cyan
    printf '%s ' (__git_tree_icon)
    set_color normal
    
    # Call original tide prompt if it exists
    if functions -q _original_tide_prompt
        _original_tide_prompt
    else
        # Fallback prompt
        set_color blue
        printf '%s' (prompt_pwd)
        set_color normal
        printf ' > '
    end
end
