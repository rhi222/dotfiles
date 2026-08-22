# git worktree削除（fzfで選択）
# -f/--force: 未コミット・未追跡ファイルがあっても削除する
#             2回指定（-ff）でlock済みworktreeも削除する
#
# lockで失敗したときは、lock理由に埋まっているpidの生死を見て
# 「終了済みセッションの残骸か / 実行中のセッションか」を提示する。
# 削除するかどうかの判断自体は人間に残す（自動unlockはしない）。
function wtd
    argparse h/help f/force -- $argv
    or return 1

    if set -q _flag_help
        echo "使い方: wtd [-f|--force]"
        echo "  -f, --force   未コミット変更があっても削除（-ff でlock済みも削除）"
        return 0
    end

    set selection (__wt_select "delete worktree")
    or return 0

    set worktree_path (echo $selection | awk '{if ($1 == "*") print $4; else print $3}')

    set -l force_args
    for i in (seq (count $_flag_force))
        set -a force_args --force
    end

    echo "削除: $worktree_path"
    set -l output (git worktree remove $force_args "$worktree_path" 2>&1)
    set -l rc $status

    test -n "$output"; and printf '%s\n' $output >&2
    test $rc -eq 0; and return 0

    __wtd_lock_hint "$worktree_path"
    return $rc
end

# lock起因の失敗であればヒントを出す。lockでなければ何もしない。
function __wtd_lock_hint --argument-names worktree_path
    set -l reason (__wt_lock_reason "$worktree_path")
    or return 0

    set -l pid (string match -rg '\(pid ([0-9]+)' -- "$reason")

    if test -z "$pid"
        echo "note: lock理由: $reason" >&2
        echo "      削除するなら 'wtd -ff' を使う" >&2
        return 0
    end

    set -l comm (ps -p $pid -o comm= 2>/dev/null | string trim)
    if test -n "$comm"
        echo "note: pid $pid ($comm) は実行中。セッションを終了してから削除する" >&2
        echo "      それでも消すなら 'wtd -ff'" >&2
    else
        echo "note: このlockは終了済みセッションの残骸 (pid $pid は不在)" >&2
        echo "      'wtd -ff' で削除できる" >&2
    end
end
