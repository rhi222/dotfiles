# docker 使用状況のキャッシュ管理
#
# `docker system df` は実測 5.2 秒かかるため、shell 起動時に同期実行してはならない。
# 集計結果を JSON にキャッシュし、起動時はそれを読むだけにする。更新は
# background + disown で投げる（13-docker-clean.fish を参照）。
#
# サブコマンド:
#   --update  docker を叩いてキャッシュを書く（stdout には出さない）
#   --read    キャッシュの JSON を出力。無い/壊れていれば return 1
#   --stale   キャッシュが TTL 超または不在なら return 0

function __docker_clean_stats --description 'docker 使用状況のキャッシュ管理'
    set -l cache (__docker_clean_cache_file)

    switch "$argv[1]"
        case --update
            __docker_clean_stats_update $cache
            return $status
        case --read
            __docker_clean_stats_read $cache
            return $status
        case --stale
            __docker_clean_stats_stale $cache
            return $status
        case '*'
            echo "__docker_clean_stats: 不明な引数: $argv" >&2
            return 2
    end
end

function __docker_clean_stats_read --description 'キャッシュを読んで JSON を出力する'
    set -l cache $argv[1]
    test -f $cache; or return 1
    jq -e . $cache >/dev/null 2>&1; or return 1
    cat $cache
end

function __docker_clean_stats_stale --description 'キャッシュが TTL 超か判定する'
    set -l cache $argv[1]

    set -l ttl_h 6
    if set -q docker_clean_cache_ttl_h; and test -n "$docker_clean_cache_ttl_h"
        set ttl_h $docker_clean_cache_ttl_h
    end

    test -f $cache; or return 0
    set -l gen (jq -r '.generated_at // 0' $cache 2>/dev/null)
    or return 0
    test -n "$gen"; or return 0
    string match -qr '^[0-9]+$' -- $gen; or return 0

    set -l age (math (date +%s) - $gen)
    test $age -ge (math "round($ttl_h * 3600)")
end

function __docker_clean_stats_update --description 'docker を叩いてキャッシュを書く'
    set -l cache $argv[1]

    docker info >/dev/null 2>&1
    or return 1

    # -sc: 複数行の JSONL を1行の配列にまとめる（多行だと fish のリストに分割されて扱いにくい）
    set -l df (docker system df --format json 2>/dev/null | jq -sc '.')
    or return 1
    test -n "$df"; or return 1

    # 稼働コンテナ: 名前 / イメージ / 稼働秒数
    set -l now (date +%s)
    set -l running_lines
    set -l ids (docker ps -q 2>/dev/null)
    if test (count $ids) -gt 0
        for line in (docker inspect --format '{{.Name}}|{{.Config.Image}}|{{.State.StartedAt}}' $ids 2>/dev/null)
            set -l f (string split '|' -- $line)
            test (count $f) -ge 3; or continue
            set -l name (string trim -l -c '/' -- $f[1])
            set -l started (date -d "$f[3]" +%s 2>/dev/null)
            test -n "$started"; or set started $now
            set -a running_lines (jq -nc \
                --arg name "$name" \
                --arg image "$f[2]" \
                --argjson up (math "$now - $started") \
                '{name: $name, image: $image, uptime_seconds: $up}')
        end
    end

    # 稼働コンテナが 0 件のとき printf は空行を出し、jq -s が [null] を作ってしまう。
    # 件数を見て明示的に [] にする。
    set -l running '[]'
    if test (count $running_lines) -gt 0
        set running (printf '%s\n' $running_lines | jq -sc '.')
        or set running '[]'
    end

    mkdir -p (path dirname $cache)
    set -l tmp $cache.tmp.$fish_pid
    jq -n \
        --argjson generated_at $now \
        --argjson df "$df" \
        --argjson running "$running" \
        '{generated_at: $generated_at, df: $df, running: $running}' >$tmp
    or begin
        rm -f $tmp
        return 1
    end
    mv $tmp $cache
end
