# gf が使う ghq list キャッシュをアトミックに更新する
#
# 更新元は2箇所ある（ghq ラッパーの同期更新と gf の background 更新）ため、
# アトミック更新の作法をここに1つだけ置いている。
#
# `command ghq` で呼ぶのは、同名の fish 関数ラッパー（ghq.fish）を経由させない
# ため。ラッパー越しでも list は更新対象サブコマンドではないので無限ループには
# ならないが、キャッシュ更新がラッパーの実装に依存する形になるのを避ける。
function __ghq_list_cache_refresh --description 'ghq list キャッシュを更新する'
    set -l cache (__ghq_list_cache_path)
    mkdir -p (dirname $cache)

    # .tmp は PID で分ける。ghq ラッパーの同期更新と gf の background 更新が
    # 同時に走りうるため、固定名だと互いの中間ファイルを踏む。
    set -l tmp $cache.$fish_pid.tmp

    # 失敗時は .tmp を残さずキャッシュも壊さない。stderr は .err に上書きして
    # 可視化する（追記だと無限に肥大する）。
    if command ghq list >$tmp 2>$cache.err
        mv $tmp $cache
    else
        rm -f $tmp
        return 1
    end
end
