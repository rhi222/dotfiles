# メインworktree（リンクworktreeではない本体）の絶対パスを返す
# gitリポジトリ外では何も出力せず return 1
#
# `git worktree list --porcelain` の先頭エントリは常にメインworktreeなので、
# リンクworktreeの中から呼んでも本体のパスが得られる。
function __wt_main_path
    set -l paths (git worktree list --porcelain 2>/dev/null | string match -rg '^worktree (.*)')
    if test (count $paths) -eq 0
        return 1
    end
    echo $paths[1]
end
