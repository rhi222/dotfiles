# fish の設定変数を環境変数へ移して dotctl を呼ぶ
#
# **独立ファイルにしてある**（__dclean_dotctl と同じ理由。起動時通知からも呼ぶ）。
#
# fish の変数は Go から読めないので、ここで環境変数へ移す。未設定のものは渡さず、
# Go 側の既定値を使わせる。
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
