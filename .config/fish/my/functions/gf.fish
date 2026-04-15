function gf --description "cd to ghq-managed repo (cached ghq list)"
    type -q ghq; or return

    set -l cache ~/.cache/ghq-list

    # 初回またはキャッシュが空ならキャッシュを同期的に作成
    if not test -s $cache
        mkdir -p ~/.cache
        ghq list >$cache
    end

    # ghq root はfzf表示前に取得（選択後の遅延を回避）
    set -l root (ghq root)

    set -l repo (fzf --bind "start:unbind(enter)" --bind "load:rebind(enter)" <$cache)
    or return

    cd $root/$repo

    # 次回用にバックグラウンドでキャッシュをアトミック更新
    fish -c "ghq list >$cache.tmp && mv $cache.tmp $cache" &
    disown
end
