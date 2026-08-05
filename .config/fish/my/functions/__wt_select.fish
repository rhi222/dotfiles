# wt/wtd共通: fzfでworktreeを選択して返す
# 選択なしの場合はreturn 1
#
# 表示行の整形とタグ判定は __wt_format_rows に分離している（テスト可能にするため）。
function __wt_select --argument-names prompt_label
    set -l main_path (__wt_main_path)

    set selection (git wt | tail -n +2 | __wt_format_rows "$main_path" | \
        fzf --ansi --reverse --height=80% \
        --prompt="$prompt_label > " \
        --preview 'echo {} | awk "{if (\$1 == \"*\") print \$3; else print \$2}" | xargs -I{} git log --oneline -10 {}')

    if test -z "$selection"
        return 1
    end

    echo $selection
end
