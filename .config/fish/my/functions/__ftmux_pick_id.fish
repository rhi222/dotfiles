# 整形済み入力（ID<区切り>表示文字列）を fzf にかけ、選ばれた行の ID 列を返す。
#
# 注: パイプで受け取った後に再度コマンド置換 `(fzf ...)` で stdin を参照しても、
#     fish はパイプの stdin を継承しない。while read で一旦吸い込んでから渡す。
#
# 区切り文字は引数で受け取る。呼び出し元の変数を --no-scope-shadowing で覗くと、
# 中で使う `set -l` が呼び出し元のローカル変数（line / parts など）を上書きしうる。
function __ftmux_pick_id --argument-names prompt delimiter
    set -l input
    while read -l l
        set -a input $l
    end

    set -l line (printf '%s\n' $input \
        | fzf --prompt="$prompt" --delimiter="$delimiter" --with-nth=2 --exit-0)
    if test -z "$line"
        return 1
    end

    set -l parts (string split $delimiter -- $line)
    echo $parts[1]
end
