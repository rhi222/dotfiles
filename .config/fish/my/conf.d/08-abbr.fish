# Abbreviations
# コマンドにコメントをつけておく、fzfでのgrepability上がるため
# https://qiita.com/wataash/items/ab0a8b86b60e782f537f#%E3%82%B3%E3%83%9E%E3%83%B3%E3%83%89%E3%81%AB%E3%82%B3%E3%83%A1%E3%83%B3%E3%83%88%E3%82%92%E3%81%A4%E3%81%91%E3%81%A6%E3%81%8A%E3%81%8F

# Git
abbr --add g git
abbr --add gbr "git for-each-ref --sort=committerdate refs/heads/ --format='%(HEAD) %(color:yellow)%(refname:short)%(color:reset) - %(color:red)%(objectname:short)%(color:reset) - %(contents:subject) - %(authorname) (%(color:green)%(committerdate:relative)%(color:reset))' # show recently touched branch"
abbr --add ggr 'cd (git rev-parse --show-toplevel)'

# Docker
abbr --add dc docker compose
# docker composeのオプション指定しやすいようにset-cursor
abbr --add dcl --set-cursor 'docker compose -f (find_docker_compose) logs -f --tail=500 % # show current repository docker compose log'
abbr --add dcd --set-cursor 'docker compose % -f (find_docker_compose) down'
abbr --add dcu --set-cursor 'docker compose % -f (find_docker_compose) up --build -d'

# Environment Variables
abbr --add cpe 'COMPOSE_PROFILES='

# Development Tools
abbr --add ld lazydocker
abbr --add lg lazygit
abbr --add gf 'cd (ghq root)/(ghq list | fzf)'
abbr --add gw 'cd (gwq get)'
