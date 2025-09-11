function mv2main -d "Move (default) or copy repo-root-relative paths to the main worktree"
    set -l op mv # デフォルトは mv
    set -l dry 0

    argparse c/copy n/dry-run -- $argv
    or begin
        echo "Usage: mv2main [--copy] [--dry-run] <repo-root-relative-path>..."
        return 2
    end
    if set -q _flag_copy
        set op cp
    end
    if set -q _flag_dry_run
        set dry 1
    end

    # 今いるワークツリーのリポジトリルート
    set -l here (git rev-parse --show-toplevel 2>/dev/null)
    if test -z "$here"
        echo "Not inside a git worktree."
        return 1
    end

    # 本体ワークツリーのルート = worktree list の最初
    set -l roots (git worktree list --porcelain | awk '/^worktree /{print $2}')
    if test (count $roots) -lt 1
        echo "Failed to detect main worktree."
        return 1
    end
    set -l mainroot $roots[1]

    if test "$here" = "$mainroot"
        echo "You are already in the main worktree: $mainroot"
        return 0
    end

    if test (count $argv) -lt 1
        echo "Usage: mv2main [--copy] [--dry-run] <repo-root-relative-path>..."
        return 2
    end

    for rel in $argv
        # "./" を削る
        if string match -q "./*" -- "$rel"
            set rel (string sub -s 3 -- "$rel")
        end

        set -l src "$here/$rel"
        set -l dest "$mainroot/$rel"
        set -l destdir (dirname "$dest")

        if not test -e "$src"
            echo "Not found under current worktree: $rel  (looked at: $src)"
            continue
        end

        if test $dry -eq 1
            echo "[dry-run] mkdir -p $destdir"
            if test "$op" = cp
                echo "[dry-run] cp -vR \"$src\" \"$dest\""
            else
                echo "[dry-run] mv -v \"$src\" \"$dest\""
            end
            continue
        end

        mkdir -p "$destdir"
        if test "$op" = cp
            cp -vR "$src" "$dest"
        else
            mv -v "$src" "$dest"
        end
    end
end
