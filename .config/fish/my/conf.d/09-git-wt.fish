# git-wt shell integration
# git worktree管理ツールの初期化
# 参考: https://koic.hatenablog.com/entry/introduce-git-wt
#
# `git wt --init fish` の出力をキャッシュして起動時のサブプロセスを回避する。
# git-wt バイナリ更新時は自動で再生成される。
if type -q git-wt
    set -l cache $HOME/.cache/git-wt-init.fish
    set -l bin (type -p git-wt)
    if not test -f $cache; or test $bin -nt $cache
        mkdir -p (path dirname $cache)
        git wt --init fish >$cache
    end
    source $cache
end
