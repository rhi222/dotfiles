# docker 使用状況のキャッシュ管理
#
# `docker system df` は実測 5.2 秒かかるため、shell 起動時に同期実行してはならない。
# 集計結果を JSON にキャッシュし、起動時はそれを読むだけにする。更新は
# background + disown で投げる（13-docker-clean.fish を参照）。
#
# サブコマンド:
#   --update        docker を叩いてキャッシュを書く（stdout には出さない）
#   --read          キャッシュの JSON を出力。無い/壊れていれば return 1
#   --stale         キャッシュが TTL 超または不在なら return 0
#   --notice        閾値超えなら通知1行を出力して return 0、そうでなければ return 1
#   --long-running  除外後の長時間稼働コンテナを name<TAB>image<TAB>秒 で列挙する

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
        case --notice
            __docker_clean_stats_notice $cache
            return $status
        case --long-running
            __docker_clean_stats_long_running $cache $argv[2..-1]
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

# キャッシュを1回の jq で読み、必要な値をプロセス内にメモ化する。
#
# 起動時フックは --notice と --stale を続けて呼ぶため、素朴に実装すると1回の
# シェル起動で jq を4回起動してしまい、実測で 0.2 秒ほど起動が遅くなる。
# 同一プロセス内では1回だけ読むようにする（__git_tree_icon が PWD 単位で
# キャッシュしているのと同じ発想）。
#
# 結果は以下のグローバルに入る:
#   __docker_clean_gen       generated_at（epoch 秒）
#   __docker_clean_reclaim   df の Type<TAB>Reclaimable のリスト
#   __docker_clean_running   稼働コンテナの name<TAB>image<TAB>秒 のリスト
function __docker_clean_stats_parse --description 'キャッシュを1回のjqで読みメモ化する'
    set -l cache $argv[1]

    if set -q __docker_clean_parsed; and test "$__docker_clean_parsed" = "$cache"
        return $__docker_clean_parse_rc
    end

    set -g __docker_clean_parsed $cache
    set -g __docker_clean_gen 0
    set -g __docker_clean_reclaim
    set -g __docker_clean_running
    set -g __docker_clean_parse_rc 1

    test -f $cache; or return 1

    set -l lines (jq -r '
        "G\t\(.generated_at // 0)",
        (.df[]? | "R\t\(.Type)\t\(.Reclaimable)"),
        (.running[]? | "C\t\(.name)\t\(.image)\t\(.uptime_seconds)")
    ' $cache 2>/dev/null)
    or return 1
    test (count $lines) -gt 0; or return 1

    for l in $lines
        set -l f (string split \t -- $l)
        switch $f[1]
            case G
                set -g __docker_clean_gen $f[2]
            case R
                set -a __docker_clean_reclaim (string join \t $f[2..-1])
            case C
                set -a __docker_clean_running (string join \t $f[2..-1])
        end
    end

    set -g __docker_clean_parse_rc 0
    return 0
end

function __docker_clean_stats_stale --description 'キャッシュが TTL 超か判定する'
    set -l cache $argv[1]

    set -l ttl_h 6
    if set -q docker_clean_cache_ttl_h; and test -n "$docker_clean_cache_ttl_h"
        set ttl_h $docker_clean_cache_ttl_h
    end

    __docker_clean_stats_parse $cache; or return 0
    string match -qr '^[0-9]+$' -- $__docker_clean_gen; or return 0

    set -l age (math (date +%s) - $__docker_clean_gen)
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

    # 内容が変わったのでプロセス内のメモを捨てる（次回の parse で読み直す）。
    # 未設定の変数に set -e すると非ゼロを返すため、最後に明示的に成功を返す。
    set -q __docker_clean_parsed; and set -e __docker_clean_parsed
    return 0
end

# 除外パターン（既定 + docker_clean_ignore_patterns による上書き）にマッチするか。
# コンテナ名とイメージ名の両方に照合する。example-org-mcp のコンテナ名は自動生成
# （suspicious_gagarin 等）で識別できないため、イメージ名側での照合が必須。
function __docker_clean_is_ignored --description 'コンテナが除外パターンにマッチするか'
    set -l ignore 'buildx_buildkit_*' '*example-org-mcp*'
    if set -q docker_clean_ignore_patterns; and test (count $docker_clean_ignore_patterns) -gt 0
        set ignore $docker_clean_ignore_patterns
    end
    for p in $ignore
        if string match -q -- $p $argv[1]; or string match -q -- $p $argv[2]
            return 0
        end
    end
    return 1
end

# 長時間稼働コンテナを name<TAB>image<TAB>uptime_seconds で出力する。
# 既定は除外パターン適用後の一覧。--excluded を付けると逆に
# 「閾値超えだが除外パターンにマッチした」側を列挙する（プレビューの注記用）。
function __docker_clean_stats_long_running --description '長時間稼働コンテナを列挙する'
    set -l cache $argv[1]
    set -l want_excluded 0
    contains -- --excluded $argv[2..-1]; and set want_excluded 1

    __docker_clean_stats_parse $cache; or return 1

    set -l thr_h 12
    if set -q docker_clean_uptime_threshold_h; and test -n "$docker_clean_uptime_threshold_h"
        set thr_h $docker_clean_uptime_threshold_h
    end
    set -l thr_s (math "round($thr_h * 3600)")

    for line in $__docker_clean_running
        set -l f (string split \t -- $line)
        test (count $f) -ge 3; or continue
        string match -qr '^[0-9]+$' -- $f[3]; or continue
        test $f[3] -gt $thr_s; or continue

        set -l ignored 0
        __docker_clean_is_ignored $f[1] $f[2]; and set ignored 1
        test $ignored -eq $want_excluded; and echo $line
    end
end

# 閾値超えなら通知 1 行を出力して return 0、そうでなければ何も出さず return 1。
function __docker_clean_stats_notice --description '起動時通知の1行を生成する'
    set -l cache $argv[1]
    __docker_clean_stats_parse $cache; or return 1

    set -l size_thr_gb 5
    if set -q docker_clean_size_threshold_gb; and test -n "$docker_clean_size_threshold_gb"
        set size_thr_gb $docker_clean_size_threshold_gb
    end
    set -l thr_h 12
    if set -q docker_clean_uptime_threshold_h; and test -n "$docker_clean_uptime_threshold_h"
        set thr_h $docker_clean_uptime_threshold_h
    end

    # 回収可能量を「軽掃除で消える分」と「重掃除でしか消えない分」に分ける。
    #
    # df の Images Reclaimable は「どのコンテナからも参照されていない image」の量で、
    # dangling かどうかは問わない。軽掃除の `image prune -f` は dangling だけを消すため、
    # ここを軽掃除の根拠にすると「dclean しても通知が消えない」状態になる（実際になった）。
    # 一方 Containers / Local Volumes / Build Cache の Reclaimable は軽掃除の
    # prune がそのまま回収する量に対応する（実測で prune 後に 0B になる）。
    set -l light_parts
    set -l heavy_parts
    for entry in $__docker_clean_reclaim
        set -l f (string split \t -- $entry)
        test (count $f) -ge 2; or continue
        switch $f[1]
            case Images
                set -a heavy_parts $f[2]
            case '*'
                set -a light_parts $f[2]
        end
    end

    set -l light_bytes 0
    if test (count $light_parts) -gt 0
        set light_bytes (__docker_clean_size_to_bytes $light_parts)
        or set light_bytes 0
    end
    set -l heavy_bytes $light_bytes
    if test (count $heavy_parts) -gt 0
        set -l extra (__docker_clean_size_to_bytes $heavy_parts)
        and set heavy_bytes (math "$light_bytes + $extra")
    end

    set -l long (count (__docker_clean_stats_long_running $cache))

    # NOTE: fish 4.x の math は論理演算子を持たないため、math で整数化してから test -ge で比較する。
    set -l thr (math "round($size_thr_gb * 1000000000)")

    # 案内するコマンドは、その量を実際に回収できるモードに合わせる。
    set -l size_msg
    set -l cmd dclean
    if test $light_bytes -ge $thr
        set size_msg (__docker_clean_format_bytes $light_bytes)" 回収可能"
    else if test $heavy_bytes -ge $thr
        set size_msg (__docker_clean_format_bytes $heavy_bytes)" 回収可能（未使用 image 中心）"
        set cmd 'dclean -a'
    end

    if test -z "$size_msg"; and test $long -eq 0
        return 1
    end

    set -l parts
    test -n "$size_msg"; and set -a parts $size_msg
    test $long -gt 0; and set -a parts "$thr_h""h超稼働 $long""件"
    test -z "$size_msg"; and set cmd 'dclean --status'

    echo "🗑  docker: "(string join ' / ' $parts)"  → $cmd"
end
