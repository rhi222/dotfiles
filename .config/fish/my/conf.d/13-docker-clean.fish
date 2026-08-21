# docker 掃除のリマインド
#
# `docker system df` は実測 5.2 秒かかるため、起動時に同期実行してはならない。
# ここではキャッシュ（$XDG_STATE_HOME/docker-clean/stats.json）を読むだけにし、
# キャッシュが古い場合の更新は background + disown に逃がす。更新結果が反映される
# のは次回の起動時になるが、リマインドの用途には十分。
#
# 判定と通知文の生成は Go 側（dotctl docker notice / stale）。閾値と除外リストは
# 以下の変数で上書きでき、dclean.fish が環境変数へ移して渡す。
#   docker_clean_size_threshold_gb    回収可能サイズの閾値（既定 5）
#   docker_clean_uptime_threshold_h   長時間稼働とみなす時間（既定 12）
#   docker_clean_ignore_patterns      長時間稼働の集計から除外する名前/イメージのグロブ
#   docker_clean_cache_ttl_h          キャッシュの TTL（既定 6）

function __docker_clean_greeting --description 'docker の溜まり具合をキャッシュから通知する'
    set -l dotctl (__dclean_dotctl 2>/dev/null)
    or return 0

    # 通知（キャッシュを読むだけ。閾値未満なら非ゼロで何も出ない）
    __dclean_env $dotctl docker notice

    # キャッシュが古ければ裏で更新する。今回の表示には反映されない。
    if __dclean_env $dotctl docker stale
        __dclean_env $dotctl docker refresh >/dev/null 2>&1 &
        # 更新が即座に終わると disown 時点でジョブが消えており
        # 「There are no suitable jobs」を出す。切り離せていれば目的は足りるので捨てる。
        disown 2>/dev/null
    end
end

# **docker の有無を見てから呼ぶ。** 未導入の端末では docker info が
# command not found ハンドラを起こし、起動のたびに snap の導入案内が出る。
if status is-interactive; and type -q docker
    __docker_clean_greeting
end
