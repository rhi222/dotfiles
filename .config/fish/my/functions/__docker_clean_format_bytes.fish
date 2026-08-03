# バイト数を人間可読な文字列にする（SI 単位、小数1桁）
#
# NOTE: fish 4.x の math は論理演算子を持たないため、比較は test -ge で行う。
function __docker_clean_format_bytes --description 'バイト数を人間可読な文字列にする'
    set -l b $argv[1]
    test -z "$b"; and set b 0

    if test $b -ge 1000000000000
        echo (math -s1 "$b / 1000000000000")"TB"
    else if test $b -ge 1000000000
        echo (math -s1 "$b / 1000000000")"GB"
    else if test $b -ge 1000000
        echo (math -s1 "$b / 1000000")"MB"
    else if test $b -ge 1000
        echo (math -s1 "$b / 1000")"kB"
    else
        echo $b"B"
    end
end
