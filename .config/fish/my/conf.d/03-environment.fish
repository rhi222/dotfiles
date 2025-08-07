# Environment variables and tool settings

set PSQL_EDITOR nvim
set GIT_EDITOR 'nvim -u $HOME/.config/nvim/init.lua'
set -gx EDITOR nvim
set -gx VISUAL nvim
set TERM screen-256color

# for copilot at with zscaler credential
set NODE_EXTRA_CA_CERTS /usr/local/share/ca-certificates/zscaler.cer

# zoxide integration
if type -q zoxide
    zoxide init fish | source
end

# tabtab source for packages
if test -f ~/.config/tabtab/fish/__tabtab.fish
    source ~/.config/tabtab/fish/__tabtab.fish
end