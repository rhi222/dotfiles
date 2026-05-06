function fkill
    set -l pids (ps aux \
        | fzf \
        --header-lines=1 \
        --multi \
        --preview 'echo {}' \
        --preview-window=down:40%:wrap \
        | awk '{print $2}')

    if test -z "$pids"
        return 0
    end

    kill -TERM $pids
end
