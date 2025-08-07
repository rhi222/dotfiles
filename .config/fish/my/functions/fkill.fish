function fkill
    ps aux \
        | fzf \
        --header-lines=1 \
        --multi \
        --preview 'echo {}' \
        --preview-window=down:40%:wrap \
        | awk '{print $2}' \
        | xargs kill -9
end