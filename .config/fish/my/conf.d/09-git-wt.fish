# git-wt shell integration
# git worktree管理ツールの初期化
# 参考: https://koic.hatenablog.com/entry/introduce-git-wt
if command -q git-wt
    git wt --init fish | source
end
