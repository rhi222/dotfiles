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

# nvm
# https://github.com/creationix/nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" # This loads nvm

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
export PATH="/home/forcia/.nvm/versions/node/v5.0.0/bin:/home/forcia/bin:/usr/local/java/bin:/usr/local/java/bin:/home/forcia/bin:/usr/local/sbin:/usr/local/bin:/usr/local/pgsql/bin:/home/forcia/.rbenv/bin:/usr/local/python/bin:/usr/local/python/bin:/home/forcia/.rbenv/shims:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/home/forcia/.fzf/bin"

# export PATH="/home/forcia/.nvm/versions/node/v5.0.0/bin:/home/forcia/bin:/usr/local/java/bin:/usr/local/java/bin:/home/forcia/bin:/usr/local/sbin:/usr/local/bin:/usr/local/pgsql/bin:/home/forcia/.rbenv/bin:/usr/local/pyenv/shims:/usr/local/pyenv/bin:/usr/local/python/bin:/home/forcia/.rbenv/shims:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/home/forcia/.fzf/bin"

function jgrep () { grep -nr `echo $1 | nkf -s` $2 | nkf -w }

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

###
# alias
###

# alias find command
# http://takuya-1st.hatenablog.jp/entry/2015/12/15/030119
function f () { find $1 -name "$2" }

# alias for catalina
alias catalina='less /usr/local/tomcat/logs/catalina.out'

# tree for exel
# https://qiita.com/yoccola/items/bac59716c88633b68b61
alias treex="tree -NF | perl -pe 's/^├── //g; s/^└── //g; s/^│\xc2\xa0\xc2\xa0\x20//g; s/├── /\t/g; s/│\xc2\xa0\xc2\xa0\x20/\t/g; s/└── /\t/g; s/    /\t/g; s/\*$//g; s/^\.\n//g;'"

# alias for cocot
alias sshe='cocot -t UTF-8 -p EUC-JP -- ssh' #EUC-JP$B4D6-$K(Bssh$B$9$k(B

# alias for neovim
alias vi='nvim'
alias view='nvim -R'

# alias for mkdir and cd
function mkdircd () { mkdir -p $1 && cd $_ }

# alias for rsync always use ssh and don't update file
function rsyncs () { rsync --ignore-existing -e ssh $1}

# alias for cd
alias ..="cd .."
alias ..2="cd ../.."
alias ..3="cd ../../.."
alias ..4="cd ../../../.."
alias ..5="cd ../../../../.."

# alias for grep
alias g='grep'
alias eg='egrep'

# alias for cd
alias cdrr="cd $(git rev-parse --show-toplevel)"

# axis2 for jetstar api
export AXIS2_HOME=/usr/local/src/axis2-1.7.6

alias estart="/home/forcia/eclipse/jee-oxygen/eclipse/eclipse -clean"


# git push 漏れ防止策
# https://qiita.com/shiraji/items/92bbe60e9ddc618e11c2
alias gbn='git rev-parse --abbrev-ref HEAD'

function glr() {
	_branch=`gbn`
	git log origin/${_branch}..${_branch}
}

function git_not_pushed {
	# git管理下にいるかどうかの確認
	if [[ "`git rev-parse --is-inside-work-tree 2>/dev/null`" = "true" ]]; then
		# HEADのハッシュを取得
		_head="`git rev-parse --verify -q HEAD 2>/dev/null`"
		if [[ $? -eq 0 ]]; then
			# origin/branch名のハッシュを取得
			### gbnはブランチ名取得のalias。上に記載してある。###
			_remote="`git rev-parse --verify -q origin/\`gbn\` 2>/dev/null`"
			if [[ $? -eq 0 ]]; then
				# 比較して、違ったら*表示。
				if [[ "${_head}" != "${_remote}" ]]; then
					echo -n "*"
				fi
			fi
		fi
	fi
}

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

RPROMPT="%1(v|%F{green}%1v%f|)`git_not_pushed`"

# ntfy
eval "$(ntfy shell-integration)"

# Growl notification
# https://github.com/dschep/ntfy
autoload -U add-zsh-hook 2>/dev/null || return

#
# Notification of local host command
# ----------------------------------
#
# Automatic notification via growlnotify / notify-send
#
#
# Notification of remote host command
# -----------------------------------
#
# "==ZSH LONGRUN COMMAND TRACKER==" is printed after long run command execution
# You can utilize it as a trigger
#
# ## Example: iTerm2 trigger( http://qiita.com/yaotti/items/3764572ea1e1972ba928 )
#
#  * Trigger regex: ==ZSH LONGRUN COMMAND TRACKER==(.*)
#  * Parameters: \1
#

__timetrack_threshold=10 # seconds
read -r -d '' __timetrack_ignore_progs <<EOF
less
emacs vi vim view
ssh mosh telnet nc netcat
gdb tmux tig man
EOF

export __timetrack_threshold
export __timetrack_ignore_progs

function __my_preexec_start_timetrack() {
    local command=$1

    export __timetrack_start=`date +%s`
    export __timetrack_command="$command"
}

function __my_preexec_end_timetrack() {
    local exec_time
    local command=$__timetrack_command
    local prog=$(echo $command|awk '{print $1}')
    local notify_method
    local message

    export __timetrack_end=`date +%s`

    if test -n "${REMOTEHOST}${SSH_CONNECTION}"; then
        notify_method="remotehost"
    elif which growlnotify >/dev/null 2>&1; then
        notify_method="growlnotify"
    elif which notify-send >/dev/null 2>&1; then
        notify_method="notify-send"
    else
        return
    fi

    if [ -z "$__timetrack_start" ] || [ -z "$__timetrack_threshold" ]; then
        return
    fi

    for ignore_prog in $(echo $__timetrack_ignore_progs); do
        [ "$prog" = "$ignore_prog" ] && return
    done

    exec_time=$((__timetrack_end-__timetrack_start))
    if [ -z "$command" ]; then
        command="<UNKNOWN>"
    fi

    message="Command finished!\nTime: $exec_time seconds\nCOMMAND: $command"

    if [ "$exec_time" -ge "$__timetrack_threshold" ]; then
        case $notify_method in
            "remotehost" )
        # show trigger string
                echo -e "\e[0;30m==ZSH LONGRUN COMMAND TRACKER==$(hostname -s): $command ($exec_time seconds)\e[m"
        sleep 1
        # wait 1 sec, and then delete trigger string
        echo -e "\e[1A\e[2K"
                ;;
            "growlnotify" )
                echo "$message" | growlnotify -n "ZSH timetracker" --appIcon Terminal
                ;;
            "notify-send" )
                notify-send "ZSH timetracker" "$message" --icon=dialog-information
                ;;
        esac
    fi

    unset __timetrack_start
    unset __timetrack_command
}

if which growlnotify >/dev/null 2>&1 ||
    which notify-send >/dev/null 2>&1 ||
    test -n "${REMOTEHOST}${SSH_CONNECTION}"; then
    add-zsh-hook preexec __my_preexec_start_timetrack
    add-zsh-hook precmd __my_preexec_end_timetrack
fi

export PATH=/home/forcia/bin/apricot-shell-1.1.1/bin:$PATH
export PATH=/data/git-repos/apricot_modules/jasmine-apricot/bin:$PATH
export APRICOT_MODULE_PATH=/data/git-repos/apricot_modules
export PSQL_EDITOR='nvim +"set syntax=sql" '

# rustup
source ~/.cargo/env


# kohno
# https://github.com/fnwiya/dotfiles/blob/master/setup/zsh/.zsh.d/fzf.zsh
function fzf-ssh () {
    local selected_host=$(cat ~/.ssh/config | grep HostName | awk '{print $2}' | fzf)
    if [ -n "$selected_host" ]; then
        BUFFER="ssh ${selected_host}"
        zle accept-line
    fi
    zle clear-screen
}
zle -N fzf-ssh
bindkey '^x^[' fzf-ssh

# change LXTerminal color schema
COLOR_SCHEME='/home/forcia/colorscheme.sh'
[[ -s $COLOR_SCHEME ]] && source $COLOR_SCHEME


set -g terminal-overrides ',xterm-256color:Tc'
