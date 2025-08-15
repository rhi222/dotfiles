# ~/.gitconfigから呼び出し
function git-fsw
    # ブランチ一覧（ローカル + リモート）、origin/HEAD 除外、重複削除
    set branch (git for-each-ref --format="%(refname:short)" refs/heads refs/remotes/origin \
        | sed 's#^remotes/##' \
        | grep -v '^origin/HEAD$' \
        | sort -u \
        | fzf --ansi --reverse --height=80% \
            --prompt="switch > " \
            --preview '
                set ref (echo {} | sed "s#^origin/#refs/remotes/origin/#; t; s#^#refs/heads/#")
                git --no-pager log --graph --decorate --date=relative \
                    --pretty=format:"%C(auto)%h %ad %an %d %s" -n 30 $ref
            ')

    if test -z "$branch"
        return 0
    end

    if git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null
        git switch "$branch"
    else

        git switch -c (string replace 'origin/' '' "$branch") --track "$branch"
    end
end
