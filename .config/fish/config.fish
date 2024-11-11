# ------------- alias setting {{{
alias g 'cd (ghq root)/(ghq list | fzf)'
#alias v 'code $(ghq root)/$(ghq list | peco)'

# open tmux in 256color
alias tmux 'tmux -2'

# jump to repository root
alias cdrr "cd (git rev-parse --show-toplevel)"

# for cocot
alias sshe 'cocot -t UTF-8 -p EUC-JP -- ssh' #EUC-JP端末へのアクセス

# for neovim
alias vi 'nvim'
alias view 'nvim -R'

# reload
alias rf 'source ~/.config/fish/config.fish'

# gitui
alias gu 'gitui'
# ------------- }}}

# ------------- abbr setting {{{
# コマンドにコメントをつけておく、fzfでのgrepability上がるため
# https://qiita.com/wataash/items/ab0a8b86b60e782f537f#%E3%82%B3%E3%83%9E%E3%83%B3%E3%83%89%E3%81%AB%E3%82%B3%E3%83%A1%E3%83%B3%E3%83%88%E3%82%92%E3%81%A4%E3%81%91%E3%81%A6%E3%81%8A%E3%81%8F
abbr --add gbr "git for-each-ref --sort=committerdate refs/heads/ --format='%(HEAD) %(color:yellow)%(refname:short)%(color:reset) - %(color:red)%(objectname:short)%(color:reset) - %(contents:subject) - %(authorname) (%(color:green)%(committerdate:relative)%(color:reset))' # show recently touched branch"
abbr --add ggr 'cd (git rev-parse --show-toplevel)'
abbr --add dc docker compose
abbr --add dcl 'docker compose -f (find_docker_compose) logs -f --tail=500 # show current repository docker compose log'
abbr --add dcd 'docker compose -f (find_docker_compose) down'
abbr --add dcu 'docker compose -f (find_docker_compose) up --build'
# function find_docker_compose
# 	# レポジトリごとの差異をfindで頑張って吸収
# 	# - compose.yaml
# 	# - docker/docker-compose.yml
# 	# - docker/compose.yaml
# 	# - etc/docker/docker-compose.yml
# 	# - docker-compose/docker-compose.yml
# 	# 指定したパターンに一致するファイルを検索
# 	find $(git rev-parse --show-toplevel) \
# 		\( \
# 			\( -path '*/etc/docker/docker-compose.yml' -o -path '*/docker/docker-compose.yml' -o -path '*/docker/compose.yaml' -o -path '*/compose.yaml' -o -path '*/docker-compose/docker-compose.yml' \) \
# 			-and \
# 			\( -name 'docker-compose.yml' -o -name 'compose.yaml' \) \
# 		\) \
# 		-print
# end

function find_docker_compose
	set search_dir (git rev-parse --show-toplevel)

	# Docker Compose ファイルの候補リスト
	set patterns \
		'*/etc/docker/docker-compose.*' \
		'*/docker/docker-compose.*' \
		'*/docker/compose.*' \
		'*/compose.*' \
		'*/docker-compose/docker-compose.*'

	# パターンに一致するファイルを検索 (yml または yaml)
	find $search_dir -type f \( \
		-path $patterns[1] -o \
		-path $patterns[2] -o \
		-path $patterns[3] -o \
		-path $patterns[4] -o \
		-path $patterns[5] \
	\) \( -name '*.yml' -o -name '*.yaml' \) -print | head -n 1
end

abbr --add cpe 'COMPOSE_PROFILES='
abbr --add ld lazydocker
abbr --add lg lazygit
# ------------- }}}

# ------------- font color setting {{{
# https://fishshell.com/docs/current/cmds/set_color.html
# https://reiichii.hateblo.jp/entry/2022/01/05/194823
set -U black brblack # 背景色と同化して読めないため
# ------------- }}}

# ------------- etc setting {{{
set PSQL_EDITOR 'nvim'
set GIT_EDITOR 'nvim -u $HOME/.config/nvim/init.lua'
# ------------- }}}

# ------------- ssh agent setting {{{
# git 操作時に毎回鍵のパスワード入力がめんどくさすぎた
set -Ux SSH_AGENT_INFO_FILE ~/.ssh-agent-info
if test -f ~/.ssh/github_rhi222
	# エージェント情報を読み込む
	if test -f $SSH_AGENT_INFO_FILE
		source $SSH_AGENT_INFO_FILE > /dev/null
	end

	# SSHエージェントが起動していない場合にのみ新しく起動
	if not set -q SSH_AUTH_SOCK
		eval (ssh-agent -c | tee $SSH_AGENT_INFO_FILE | source > /dev/null)
		ssh-add ~/.ssh/github_rhi222 > /dev/null
	end
end
# ------------- }}}


# ------------- path setting {{{
# path設定はfish_add_pathを利用
# https://zenn.dev/estra/articles/zenn-fish-add-path-final-answer

# for golang
# https://tech.librastudio.co.jp/entry/index.php/2018/02/20/post-1792/
set GOPATH $HOME/go
fish_add_path $GOPATH/bin
fish_add_path $HOME/go/bin

# for deno
set DENO_INSTALL $HOME/.deno
fish_add_path $DENO_INSTALL/bin

# for pip3
fish_add_path $HOME/.local/bin

# for fzf
fish_add_path $HOME/.fzf/bin

# volta setting
# https://docs.volta.sh/guide/getting-started
# http://gitlab.fdev/webconnect/material/material_registration/-/merge_requests/6511
set VOLTA_FEATURE_PNPM 1
set -gx VOLTA_HOME "$HOME/.volta"
fish_add_path $VOLTA_HOME/bin

# for win32yank
# https://qiita.com/v2okimochi/items/f53edcf79a4b71f519b1#%E3%83%9E%E3%82%A6%E3%82%B9%E6%93%8D%E4%BD%9C%E3%82%84%E3%82%AF%E3%83%AA%E3%83%83%E3%83%97%E3%83%9C%E3%83%BC%E3%83%89%E5%85%B1%E6%9C%89%E3%82%92%E8%A8%AD%E5%AE%9A%E3%81%99%E3%82%8B
fish_add_path $HOME/bin

# docker setting
# https://qiita.com/v2okimochi/items/f53edcf79a4b71f519b1#wsl2%E3%81%AEpath%E3%81%8B%E3%82%89windows%E3%83%91%E3%82%B9%E3%82%92%E6%8A%9C%E3%81%8F
fish_add_path /mnt/c/Program\ Files/Docker/Docker/resources/bin

# rust setting
fish_add_path $HOME/.cargo/bin

set TERM screen-256color

# for copilot at with zscaler credential
set NODE_EXTRA_CA_CERTS /usr/local/share/ca-certificates/zscaler.cer

# bun
set --export BUN_INSTALL "$HOME/.bun"
fish_add_path $BUN_INSTALL/bin

# Rye
# https://github.com/astral-sh/rye
set -Ua fish_user_paths "$HOME/.rye/shims"
# ------------- }}}


# ------------- prompt setting {{{
# now use tide. install via fisher
# https://github.com/IlanCosman/tide
# shorten current directory length
# https://github.com/IlanCosman/tide/issues/227
set -U tide_prompt_min_cols 10000
# right promptは非表示
# ターミナルコピペ時に不便なため
# items(list)は空で設定
# https://github.com/IlanCosman/tide/wiki/Configuration#right_prompt
set -U tide_right_prompt_items
# ------------- }}}

# tabtab source for packages
# uninstall by removing these lines
[ -f ~/.config/tabtab/fish/__tabtab.fish ]; and . ~/.config/tabtab/fish/__tabtab.fish; or true

# https://github.com/ajeetdsouza/zoxide
zoxide init fish | source
