# docker の不要リソースを掃除する（軽/重 2段プリセット）
#
# 実装は Go 側（internal/docker）にある。**この関数を残しているのは、
# `dclean` という呼び名と fish の補完・abbr がこの名前に紐づいているため。**
#
# 稼働中コンテナは一切停止しない。一覧を表示するだけで、停止は手動判断とする。
# named volume も削除しない（volume prune に -a を付けない）。DB データを守るため。
#
# 閾値と除外リストは fish の変数で設定する（99-local.fish など）。**fish の変数は
# Go から読めないので、ここで環境変数へ移して渡す。**
#   docker_clean_size_threshold_gb    回収可能サイズの閾値（既定 5）
#   docker_clean_uptime_threshold_h   長時間稼働とみなす時間（既定 12）
#   docker_clean_ignore_patterns      長時間稼働の集計から除外する名前/イメージのグロブ
#   docker_clean_cache_ttl_h          キャッシュの TTL（既定 6）
#   docker_clean_cache_file           キャッシュの置き場（テストで差し替える）
function dclean --description 'docker の不要リソースを掃除する（軽/重プリセット）'
    set -l dotctl (__dclean_dotctl)
    or return 1

    switch "$argv[1]"
        case --refresh
            __dclean_env $dotctl docker refresh
            return $status
    end

    __dclean_env $dotctl docker clean $argv
end
