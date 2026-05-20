# Environment variables and tool settings

set -gx PSQL_EDITOR nvim
set -gx GIT_EDITOR "nvim -u $HOME/.config/nvim/init.lua"
set -gx EDITOR nvim
set -gx VISUAL nvim
if set -q TMUX
    set -gx TERM tmux-256color
end

# WSL2: open URLs in Windows default browser (e.g. aws sso login)
if test -n "$WSL_DISTRO_NAME"; and type -q wslview
    set -gx BROWSER wslview
end

# 初回セットアップ手順は scripts/initial-setup.md を参照
# （fish_color_* など、universal変数として手動設定が必要なものをまとめている）

# zoxide integration
if type -q zoxide
    zoxide init fish | source
end

# tabtab source for packages
if test -f ~/.config/tabtab/fish/__tabtab.fish
    source ~/.config/tabtab/fish/__tabtab.fish
end
