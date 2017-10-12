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

# path
export JAVA_HOME=/usr/local/java
export PATH=$JAVA_HOME/bin:$PATH
export PATH="/home/forcia/.nvm/versions/node/v5.0.0/bin:/home/forcia/bin:/usr/local/java/bin:/usr/local/java/bin:/home/forcia/bin:/usr/local/sbin:/usr/local/bin:/usr/local/pgsql/bin:/home/forcia/.rbenv/bin:/usr/local/pyenv/shims:/usr/local/pyenv/bin:/usr/local/python/bin:/home/forcia/.rbenv/shims:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/home/forcia/.fzf/bin"

function jgrep () { grep -nr `echo $1 | nkf -s` $2 | nkf -w }

# alias for cocot
alias sshe='cocot -t UTF-8 -p EUC-JP -- ssh' #EUC-JP$B4D6-$K(Bssh$B$9$k(B

# alias for neovim
alias vi='nvim'
alias view='nvim -R'

# alias for mkdir and cd
function mkdircd () { mkdir -p $1 && cd $_ }

# alias for rsync always use ssh and don't update file
function rsyncs () { rsync --ignore-existing -e ssh $1}

# pyenv
export PYENV_ROOT=$HOME/.pyenv
export PATH=$PYENV_ROOT/bin:$PATH
eval "$(pyenv init -)"

# editor
EDITOR=nvim


# fzf
#function vi () { nvim $(fzf) }

# fd - cd to selected directory
fd() {
  local dir
  dir=$(find ${1:-*} -path '*/\.*' -prune \
                  -o -type d -print 2> /dev/null | fzf +m) &&
  cd "$dir"
}

# alias for catalina
alias catalina='less /usr/local/tomcat/logs/catalina.out'

# tree for exel
# https://qiita.com/yoccola/items/bac59716c88633b68b61
alias treex="tree -NF | perl -pe 's/^├── //g; s/^└── //g; s/^│\xc2\xa0\xc2\xa0\x20//g; s/├── /\t/g; s/│\xc2\xa0\xc2\xa0\x20/\t/g; s/└── /\t/g; s/    /\t/g; s/\*$//g; s/^\.\n//g;'"
