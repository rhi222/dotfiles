# Environment variables and tool settings

set -gx PSQL_EDITOR nvim
set -gx GIT_EDITOR 'nvim -u $HOME/.config/nvim/init.lua'
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx TERM screen-256color

# Font color settings
# https://fishshell.com/docs/current/cmds/set_color.html
# https://reiichii.hateblo.jp/entry/2022/01/05/194823
set -U black brblack # 背景色と同化して読めないため

# zoxide integration
if type -q zoxide
    zoxide init fish | source
end

# tabtab source for packages
if test -f ~/.config/tabtab/fish/__tabtab.fish
    source ~/.config/tabtab/fish/__tabtab.fish
end
