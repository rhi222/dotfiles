# wt/wtd共通: fzfでworktreeを選択して返す
# 選択なしの場合はreturn 1
function __wt_select --argument-names prompt_label
    set selection (git wt | tail -n +2 | \
        awk '{if ($1 == "*") {tag=($2 ~ /\.wt/) ? ".wt" : "main"; print "* ["tag"] "$3" "$2" "$4} else {tag=($1 ~ /\.wt/) ? ".wt" : "main"; print "  ["tag"] "$2" "$1" "$3}}' | \
        fzf --ansi --reverse --height=80% \
        --prompt="$prompt_label > " \
        --preview 'echo {} | awk "{if (\$1 == \"*\") print \$3; else print \$2}" | xargs -I{} git log --oneline -10 {}')

    if test -z "$selection"
        return 1
    end

    echo $selection
end
