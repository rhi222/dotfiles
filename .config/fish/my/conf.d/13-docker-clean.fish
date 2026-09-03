# docker 掃除のリマインド
#
# `docker system df` は実測 5.2 秒かかるため、起動時に同期実行してはならない。
# ここではキャッシュ（$XDG_STATE_HOME/docker-clean/stats.json）を読むだけにし、
# キャッシュが古い場合の更新は background + disown に逃がす。更新結果が反映される
# のは次回の起動時になるが、リマインドの用途には十分。
#
# 判定と通知文の生成は Go 側（dotctl docker notice）。閾値と除外リストは
# 以下の変数で上書きでき、dclean.fish が環境変数へ移して渡す。
#   docker_clean_size_threshold_gb    回収可能サイズの閾値（既定 5）
#   docker_clean_uptime_threshold_h   長時間稼働とみなす時間（既定 12）
#   docker_clean_ignore_patterns      長時間稼働の集計から除外する名前/イメージのグロブ
#   docker_clean_cache_ttl_h          キャッシュの TTL（既定 6）

# **呼び出しは config.fish の conf.d ループ後。** ここで直接呼ぶと
# 99-local.fish の docker_clean_ignore_patterns がまだ未設定で、除外したはずの
# コンテナを通知が数える（通知は 2件、dclean --status は 0件 という食い違いになった）。
function __docker_clean_greeting --description 'docker の溜まり具合をキャッシュから通知する'
    status is-interactive; or return 0
    type -q docker; or return 0

    set -l dotctl (__dclean_dotctl 2>/dev/null)
    or return 0

    # 通知と stale 判定を1回で行う。キャッシュが古ければ終了コード0になり、
    # 裏で更新する。今回の表示には反映されない。
    if __dclean_env $dotctl docker notice
        __dclean_env $dotctl docker refresh >/dev/null 2>&1 &
        # 更新が即座に終わると disown 時点でジョブが消えており
        # 「There are no suitable jobs」を出す。切り離せていれば目的は足りるので捨てる。
        disown 2>/dev/null
    end
end
