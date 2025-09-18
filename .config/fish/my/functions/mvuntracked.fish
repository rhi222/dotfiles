# .config/fish/my/functions/mv2main.fish のwrapper
function mvuntracked -d "Move/copy all untracked files to main worktree"
    # 外側の(=ユーザが mvuntracked に付けた)引数を保持
    set -l forward $argv

    # NULセーフ & 大量引数対策(-n 200で分割)
    git ls-files --others --exclude-standard --full-name -z \
        | xargs -0 -n 200 fish -c 'mv2main $argv' -- $forward --
end
