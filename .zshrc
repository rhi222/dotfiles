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
setopt hist_reduce_blanks # 余分なスペースを削除してヒストリに保存する
setopt hist_ignore_all_dups # 入力したコマンドがすでにコマンド履歴に含まれる場合、履歴から古いほうのコマンドを削除する

# show branch info
# http://mollifier.hatenablog.com/entry/20090814/p1
autoload -Uz vcs_info
zstyle ':vcs_info:*' formats '(%s)-[%b]'
zstyle ':vcs_info:*' actionformats '(%s)-[%b|%a]'
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
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../,,'
