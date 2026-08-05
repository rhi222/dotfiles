# gf が使う ghq list キャッシュのパスを返す
#
# gf と ghq ラッパーの両方から呼ぶため独立ファイルにしてある。fish の autoload は
# 関数名とファイル名の一致を要求するので、どちらかに同居させると
# 「先に相手を呼んでいないと未定義」という順序依存が生まれる
# （__docker_clean_cache_file と同じ理由）。
#
# テストは $ghq_list_cache を設定して実キャッシュを避ける。
function __ghq_list_cache_path --description 'ghq list キャッシュのパスを返す'
    if set -q ghq_list_cache; and test -n "$ghq_list_cache"
        echo $ghq_list_cache
    else
        echo $HOME/.cache/ghq-list
    end
end
