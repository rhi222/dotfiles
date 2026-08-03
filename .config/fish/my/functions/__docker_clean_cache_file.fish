# docker-clean のキャッシュファイルのパスを返す
#
# dclean からも直接呼ぶため独立ファイルにしてある。fish の autoload は関数名と
# ファイル名の一致を要求するので、__docker_clean_stats.fish に同居させると
# 「__docker_clean_stats を先に呼んでいないと未定義」という順序依存が生まれる。
#
# テストは $docker_clean_cache_file を設定して実キャッシュを避ける。
function __docker_clean_cache_file --description 'docker-clean キャッシュのパスを返す'
    if set -q docker_clean_cache_file; and test -n "$docker_clean_cache_file"
        echo $docker_clean_cache_file
    else if set -q XDG_STATE_HOME; and test -n "$XDG_STATE_HOME"
        echo $XDG_STATE_HOME/docker-clean/stats.json
    else
        echo $HOME/.local/state/docker-clean/stats.json
    end
end
