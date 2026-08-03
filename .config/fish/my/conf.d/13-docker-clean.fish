# docker 掃除のリマインド
#
# `docker system df` は実測 5.2 秒かかるため、起動時に同期実行してはならない。
# ここではキャッシュ（$XDG_STATE_HOME/docker-clean/stats.json）を読むだけにし、
# キャッシュが古い場合の更新は background + disown に逃がす。更新結果が反映される
# のは次回の起動時になるが、リマインドの用途には十分。
#
# 閾値と除外リストは以下の変数で上書きできる（99-local.fish などで設定する）。
#   docker_clean_size_threshold_gb    回収可能サイズの閾値（既定 5）
#   docker_clean_uptime_threshold_h   長時間稼働とみなす時間（既定 12）
#   docker_clean_ignore_patterns      長時間稼働の集計から除外する名前/イメージのグロブ
#   docker_clean_cache_ttl_h          キャッシュの TTL（既定 6）

function __docker_clean_greeting --description 'docker の溜まり具合をキャッシュから通知する'
    # 通知（キャッシュを読むだけ。閾値未満なら非ゼロで何も出ない）
    __docker_clean_stats --notice

    # キャッシュが古ければ裏で更新する。今回の表示には反映されない。
    if __docker_clean_stats --stale
        __docker_clean_stats --update >/dev/null 2>&1 &
        disown
    end
end

if status is-interactive
    __docker_clean_greeting
end
