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

# set GOROOT /usr/local/go
# set GOPATH $HOME/go
# set PATH $PATH $GOROOT/bin

# https://tech.librastudio.co.jp/entry/index.php/2018/02/20/post-1792/
set GOPATH $HOME/go
set PATH $PATH $GOPATH/bin

# set -x PATH $HOME/.pyenv/bin $PATH
# eval (pyenv init - | source)
#. (pyenv init - | psub)

# volta setting
# https://docs.volta.sh/guide/getting-started
set VOLTA_HOME $HOME/.volta
set PATH $PATH $VOLTA_HOME/bin

# for win32yank
# https://qiita.com/v2okimochi/items/f53edcf79a4b71f519b1#%E3%83%9E%E3%82%A6%E3%82%B9%E6%93%8D%E4%BD%9C%E3%82%84%E3%82%AF%E3%83%AA%E3%83%83%E3%83%97%E3%83%9C%E3%83%BC%E3%83%89%E5%85%B1%E6%9C%89%E3%82%92%E8%A8%AD%E5%AE%9A%E3%81%99%E3%82%8B
set PATH $PATH $HOME/bin

# docker setting
# https://qiita.com/v2okimochi/items/f53edcf79a4b71f519b1#wsl2%E3%81%AEpath%E3%81%8B%E3%82%89windows%E3%83%91%E3%82%B9%E3%82%92%E6%8A%9C%E3%81%8F
set PATH $PATH /mnt/c/Program\ Files/Docker/Docker/resources/bin

# rust setting
set PATH $PATH $HOME/.cargo/bin

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
