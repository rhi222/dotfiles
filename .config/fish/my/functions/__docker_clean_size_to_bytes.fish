# Docker の人間可読サイズ文字列をバイト数に変換して合算する
#
# docker system df / docker images / docker buildx du はサイズを `4.128kB` や
# `577.8MB*` のような文字列でしか返さず、生バイト数のフィールドを持たない。
# 単位は SI（kB = 1000）。`*` は共有レイヤのマーク、`(51%)` は df の割合注記で、
# どちらも数値としては無視する。
function __docker_clean_size_to_bytes --description 'Docker の人間可読サイズ文字列をバイト数に変換する'
    set -l total 0

    for raw in $argv
        # `12.53GB (51%)` の括弧以降と、共有マークの `*` を落とす
        set -l s (string replace -r '\s*\(.*$' '' -- $raw | string trim | string trim -c '*')
        test -z "$s"; and continue

        set -l m (string match -r '^([0-9]+(?:\.[0-9]+)?)\s*([kKMGTP]?i?B)$' -- $s)
        if test (count $m) -lt 3
            echo "__docker_clean_size_to_bytes: 解釈できないサイズ: $raw" >&2
            return 1
        end

        set -l mult 1
        switch $m[3]
            case B
                set mult 1
            case kB KB
                set mult 1000
            case MB
                set mult 1000000
            case GB
                set mult 1000000000
            case TB
                set mult 1000000000000
            case PB
                set mult 1000000000000000
            case KiB
                set mult 1024
            case MiB
                set mult 1048576
            case GiB
                set mult 1073741824
            case TiB
                set mult 1099511627776
            case PiB
                set mult 1125899906842624
            case '*'
                echo "__docker_clean_size_to_bytes: 未知の単位: $raw" >&2
                return 1
        end

        set total (math "round($total + $m[2] * $mult)")
    end

    echo $total
end
