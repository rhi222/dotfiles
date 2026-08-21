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

# dotctl の場所を解く。$HOME/.local/bin を優先し、無ければ PATH から引く。
function __dclean_dotctl --description 'dotctl の場所を解く'
    if test -x "$HOME/.local/bin/dotctl"
        echo "$HOME/.local/bin/dotctl"
        return 0
    end
    set -l p (command -v dotctl 2>/dev/null)
    if test -n "$p"
        echo $p
        return 0
    end
    echo "dclean: dotctl が見つからない。ビルドする: bash scripts/setup-dotctl.sh" >&2
    return 1
end

# fish の設定変数を環境変数へ移して dotctl を呼ぶ。
function __dclean_env --description 'fish の設定を環境変数へ移して dotctl を呼ぶ'
    set -l e
    if set -q docker_clean_size_threshold_gb; and test -n "$docker_clean_size_threshold_gb"
        set -a e DOCKER_CLEAN_SIZE_THRESHOLD_GB=$docker_clean_size_threshold_gb
    end
    if set -q docker_clean_uptime_threshold_h; and test -n "$docker_clean_uptime_threshold_h"
        set -a e DOCKER_CLEAN_UPTIME_THRESHOLD_H=$docker_clean_uptime_threshold_h
    end
    if set -q docker_clean_cache_ttl_h; and test -n "$docker_clean_cache_ttl_h"
        set -a e DOCKER_CLEAN_CACHE_TTL_H=$docker_clean_cache_ttl_h
    end
    if set -q docker_clean_cache_file; and test -n "$docker_clean_cache_file"
        set -a e DOCKER_CLEAN_CACHE_FILE=$docker_clean_cache_file
    end
    # **改行区切りで渡す。** グロブに空白が入ることは無いが、区切りを空白に
    # すると将来の値で壊れる。
    #
    # **`string collect` が要る。** fish のコマンド置換は改行で分割するので、
    # 付けないと2要素になり `env` が2つ目をコマンド名として扱う（実際に踏んだ）。
    if set -q docker_clean_ignore_patterns; and test (count $docker_clean_ignore_patterns) -gt 0
        set -a e DOCKER_CLEAN_IGNORE_PATTERNS=(string join \n -- $docker_clean_ignore_patterns | string collect)
    end
    env $e $argv
end
