# dotctl の場所を返す
#
# **独立ファイルにしてある。** dclean と 13-docker-clean.fish（起動時通知）の両方から
# 呼ぶが、fish の autoload は関数名とファイル名の一致を要求するので、dclean.fish に
# 同居させると「dclean を先に呼んでいないと未定義」になる。実際に起動時通知が
# `__dclean_dotctl: command not found` で落ちた（__docker_clean_cache_file と
# __ghq_list_cache_path が独立している理由と同じ）。
#
# $HOME/.local/bin を優先し、無ければ PATH から引く。cron と hook の最小 PATH でも
# 引けるようにするため。
function __dclean_dotctl --description 'dotctl の場所を返す'
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
