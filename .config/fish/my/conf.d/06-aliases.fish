# Aliases

# Git
alias gu gitui

# Terminal & Tools
alias rf 'exec fish' # reload fish config (replace process, clears stale functions/vars)

# SSH
if type -q cocot
    alias sshe 'cocot -t UTF-8 -p EUC-JP -- ssh' # EUC-JP端末へのアクセス
end
