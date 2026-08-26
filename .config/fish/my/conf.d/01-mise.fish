# mise (runtime manager) settings
# `mise activate fish` の出力をキャッシュして起動時のサブプロセスを回避する。
# mise バイナリ更新時は自動で再生成される（バイナリの mtime と比較）。
if type -q mise
    set -l cache $HOME/.cache/mise-activate.fish
    set -l mise_bin (type -p mise)
    if not test -f $cache; or test $mise_bin -nt $cache
        mkdir -p (path dirname $cache)
        mise activate fish >$cache
    end
    source $cache
end
