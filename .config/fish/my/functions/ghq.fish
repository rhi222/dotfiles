# ghq のラッパー。リポジトリ集合が変わる操作の後に gf のキャッシュを更新する。
#
# gf はキャッシュを表示するだけなので、clone しただけでは次の gf に新リポジトリが
# 出てこない。gf 側の background 更新に任せると「一度どこかへ cd するまで反映され
# ない」ため、増減させた本人であるここで確実に更新する。
#
# 更新は同期で行う。`ghq list` は実測 0.18 秒（43 リポジトリ）で、これから数秒
# かかる clone の直後に足す分としては無視できる。background にすると
# 「clone 直後の gf に間に合う」保証がなくなり、直したいことが直らない。
# `--wraps ghq` は付けていない。関数名と同じなので自己参照で無効になるうえ、
# ghq は fish 補完を同梱しておらず（`complete | grep ghq` が 0 件）、
# ラッパー有無にかかわらず補完はファイル名補完のままで差が出ない。
function ghq --description 'ghq（get などの後に gf のキャッシュを更新）'
    command ghq $argv
    set -l st $status

    # 対象は ghq 1.10.1 でリポジトリが増減するサブコマンド。
    # 読み取り系（list / root / help）では更新しない。
    # $argv が空でも contains の第1引数が空文字になるだけでエラーにはならない。
    if test $st -eq 0; and contains -- $argv[1] get clone rm create migrate
        __ghq_list_cache_refresh
    end

    return $st
end
