# Custom prompt settings (extends tide)
# Add git tree icon to tide prompt
# __git_tree_icon は functions/__git_tree_icon.fish に分離（autoload + PWDキャッシュ）

# Save original tide prompt before overriding
# NOTE: rf（再source）時の無限再帰を防ぐため、既にコピー済みならスキップ
if functions -q fish_prompt; and not functions -q _original_tide_prompt
    functions -c fish_prompt _original_tide_prompt
end

# Wrap tide's prompt to add git tree icon
function fish_prompt
    set_color cyan
    printf '%s ' (__git_tree_icon)
    set_color normal

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
