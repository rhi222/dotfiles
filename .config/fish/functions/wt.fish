# git worktree を統一の置き場所に作成するヘルパー。
#
# 置き場所: ~/git-worktrees/<host>/<org>/<repo>/<branch>
#   例: ~/git-worktrees/github.com/forcia/kkg_booking/feat/foo
#
# 使い方:
#   wt <branch>                 既存ブランチを worktree 化
#   wt <new-branch> <base-ref>  base-ref から新規ブランチを作って worktree 化
#   wt -n <branch>              作成せず、作成先パスとコマンドだけ表示（dry-run）
#
# 作成後はその worktree へ cd する。
function wt --description 'Create a git worktree under ~/git-worktrees/<host>/<org>/<repo>/<branch>'
    argparse h/help n/dry-run -- $argv
    or return

    if set -q _flag_help; or test (count $argv) -eq 0
        echo "usage: wt [-n|--dry-run] <branch> [<base-ref>]"
        echo "  既存ブランチをworktree化:        wt <branch>"
        echo "  新規ブランチを作ってworktree化:  wt <new-branch> <base-ref>   例: wt feat/foo origin/main"
        echo "  置き場所: ~/git-worktrees/<host>/<org>/<repo>/<branch>"
        return 0
    end

    if not git rev-parse --show-toplevel >/dev/null 2>&1
        echo "wt: git リポジトリ内で実行してください" >&2
        return 1
    end

    set -l branch $argv[1]
    set -l base $argv[2]

    set -l url (git config --get remote.origin.url 2>/dev/null)
    if test -z "$url"
        echo "wt: remote.origin.url が取得できません" >&2
        return 1
    end

    # URL から host と org/repo を導出
    #   git@github.com:forcia/kkg_booking.git
    #   https://github.com/forcia/kkg_booking.git
    #   ssh://git@github.com/forcia/kkg_booking.git
    set -l host (string replace -r '^(?:ssh://)?(?:git@|https?://)?([^/:]+)[/:].*$' '$1' -- $url)
    set -l slug (string replace -r '^.*[/:]([^/]+/[^/]+?)(?:\.git)?$' '$1' -- $url)

    if test -z "$host"; or test -z "$slug"
        echo "wt: URL の解析に失敗しました: $url" >&2
        return 1
    end

    set -l dest "$HOME/git-worktrees/$host/$slug/$branch"

    if set -q _flag_dry_run
        echo "dest: $dest"
        if test -n "$base"
            echo "cmd:  git worktree add -b $branch $dest $base"
        else
            echo "cmd:  git worktree add $dest $branch"
        end
        return 0
    end

    if test -d "$dest"
        echo "wt: 既に存在します。移動します: $dest"
        cd "$dest"
        return 0
    end

    if test -n "$base"
        git worktree add -b $branch "$dest" $base
        or return
    else
        git worktree add "$dest" $branch
        or return
    end

    echo "created: $dest"
    cd "$dest"
end
