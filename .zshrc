#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# Customize to your needs...
# for fzf
# https://github.com/junegunn/fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# History Configuration
# http://news.mynavi.jp/column/zsh/003/
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt hist_ignore_dups     # ignore duplication command history list
setopt share_history        # share command history data
setopt hist_reduce_blanks # $BM>J,$J%9%Z!<%9$r:o=|$7$F%R%9%H%j$KJ]B8$9$k(B
setopt hist_ignore_all_dups # $BF~NO$7$?%3%^%s%I$,$9$G$K%3%^%s%IMzNr$K4^$^$l$k>l9g!"MzNr$+$i8E$$$[$&$N%3%^%s%I$r:o=|$9$k(B

# show branch info
# http://mollifier.hatenablog.com/entry/20100113/p1
autoload -Uz vcs_info
setopt PROMPT_SUBST
zstyle ':vcs_info:*' enable git svn hg bzr           # new
zstyle ':vcs_info:*' formats '(%s)-[%b]'
zstyle ':vcs_info:*' actionformats '(%s)-[%b|%a]'
zstyle ':vcs_info:(svn|bzr):*' branchformat '%b:r%r' # new
zstyle ':vcs_info:bzr:*' use-simple true             # new
precmd () {
    psvar=()
    LANG=en_US.UTF-8 vcs_info
    [[ -n "$vcs_info_msg_0_" ]] && psvar[1]="$vcs_info_msg_0_"
}
RPROMPT="%1(v|%F{green}%1v%f|)"

# alias find command
# http://takuya-1st.hatenablog.jp/entry/2015/12/15/030119
function f () { find $1 -name "$2" }

# nvm
# https://github.com/creationix/nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" # This loads nvm

# alias for cd
alias ..="cd .."
alias ..2="cd ../.."
alias ..3="cd ../../.."
alias ..4="cd ../../../.."
alias ..5="cd ../../../../.."

# current directory$B$H(Buser name$B$r(B2$B9T$GI=<((B
# http://webtech-walker.com/archive/2008/12/15101251.html
# color
# https://h2ham.net/zsh-prompt-color
autoload colors
colors
PROMPT="
 %{${fg[cyan]}%}%~%{${reset_color}%} 
 [%n@%m]$ "
PROMPT2='[%n]> ' 

# pyenv setting
# http://qiita.com/ms-rock/items/6e4498a5963f3d9c4a67
export PYENV_ROOT=${HOME}/.pyenv
if [ -d "${PYENV_ROOT}" ]; then
	export PATH=${PYENV_ROOT}/bin:$PATH
	eval "$(pyenv init -)"
	eval "$(pyenv virtualenv-init -)"
fi
