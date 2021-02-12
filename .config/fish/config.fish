# ------------- alias setting {{{
alias g 'cd (ghq root)/(ghq list | fzf)'
#alias v 'code $(ghq root)/$(ghq list | peco)'

# open tmux in 256color
alias tmux 'tmux -2'

# jump to repository root
alias cdrr "cd (git rev-parse --show-toplevel)"

# alias for cocot
alias sshe 'cocot -t UTF-8 -p EUC-JP -- ssh' #EUC-JP端末へのアクセス

# alias for neovim
alias vi 'nvim'
alias view 'nvim -R'

# reload
alias rf 'source ~/.config/fish/config.fish'
# ------------- }}}

# ------------- etc setting {{{
set PSQL_EDITOR 'nvim'
# evalの設定方法
# bashrc での rbenv の設定
# eval "$(rbenv init -)" と同様のことを書きたい時
# https://github.com/fish-shell/fish-shell/issues/1820
# eval (rbenv init - | source)
# ------------- }}}

# ------------- path setting {{{
# set JAVA_HOME /usr/local/java
# set PATH $JAVA_HOME/bin $PATH
# set PATH /home/forcia/.nvm/versions/node/v5.0.0/bin /home/forcia/bin /usr/local/java/bin /usr/local/java/bin /home/forcia/bin /usr/local/sbin /usr/local/bin /usr/local/pgsql/bin /home/forcia/.rbenv/bin /usr/local/python/bin /usr/local/python/bin /home/forcia/.rbenv/shims /usr/sbin /usr/bin /sbin /bin /usr/games /usr/local/games /home/forcia/.fzf/bin /home/forcia/anaconda3/bin $PATH

set GOROOT /usr/local/go
set GOPATH $HOME
set PATH $PATH $GOROOT/bin
# set -x PATH $HOME/.pyenv/bin $PATH
# eval (pyenv init - | source)
#. (pyenv init - | psub)

set TERM screen-256color
# ------------- }}}


# ------------- nvm setting {{{
#eval (nvm use v12.13.0 | source)
# ------------- }}}


# ------------- prompt setting {{{
# https://github.com/oh-my-fish/oh-my-fish
# https://github.com/oh-my-fish/theme-bobthefish

# Fish git prompt
set __fish_git_prompt_showdirtystate 'yes'
set __fish_git_prompt_showstashstate 'yes'
set __fish_git_prompt_showuntrackedfiles 'yes'
set __fish_git_prompt_showupstream 'yes'
set __fish_git_prompt_color_branch yellow
set __fish_git_prompt_color_upstream_ahead green
set __fish_git_prompt_color_upstream_behind red

# Status Chars
set __fish_git_prompt_char_dirtystate '⚡'
set __fish_git_prompt_char_stagedstate '→'
set __fish_git_prompt_char_untrackedfiles '☡'
set __fish_git_prompt_char_stashstate '↩'
set __fish_git_prompt_char_upstream_ahead '+'
set __fish_git_prompt_char_upstream_behind '-'

# function fish_right_prompt
#     # Git
#     set last_status $status
#     printf '%s ' (__fish_git_prompt)
#     set_color normal
# end
# ------------- }}}
