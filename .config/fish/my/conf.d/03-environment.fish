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

# fish_color_* など universal 変数として手動設定が必要なものは docs/bootstrap.md を参照

# mod 777 ディレクトリの ls 表示色を上書き（既定の青字/緑背景は配色によって読みづらいため）
set -gx LS_COLORS "$LS_COLORS:ow=01;33:tw=01;33"

# zoxide integration
# `zoxide init fish` の出力をキャッシュして起動時のサブプロセスを回避する（01-mise.fish と同じパターン）
if type -q zoxide
    set -l cache $HOME/.cache/zoxide-init.fish
    set -l zoxide_bin (type -p zoxide)
    if not test -f $cache; or test $zoxide_bin -nt $cache
        mkdir -p (path dirname $cache)
        zoxide init fish >$cache
    end
    source $cache
end

# tabtab source for packages
if test -f ~/.config/tabtab/fish/__tabtab.fish
    source ~/.config/tabtab/fish/__tabtab.fish
end
