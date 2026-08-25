# クリップボードの折返し由来の改行を畳んでコマンドラインへ挿入する
#
# 判定と連結は __unwrap_wrapped_text が持つ。ここはクリップボードの読み口だけを決める。
# 通常の貼り付け（ctrl-v = fish_clipboard_paste）は触らない。複数行のスクリプトや
# heredoc を貼るときは改行を保ったまま貼りたいので、畳む側は専用キーに寄せる。
function unwrap-paste --description 折返し由来の改行を畳んでコマンドラインへ貼る
    set -l reader
    if type -q win32yank.exe
        # WSL2。読み出しのフラグは --lf（CRLF を LF に直す）。-o に --crlf は無い
        set reader win32yank.exe -o --lf
    else if type -q wl-paste
        set reader wl-paste --no-newline
    else if type -q xclip
        set reader xclip -selection clipboard -o
    else if type -q pbpaste
        set reader pbpaste
    else
        echo "unwrap-paste: クリップボードを読むコマンドが無い（win32yank.exe / wl-paste / xclip / pbpaste）" >&2
        return 1
    end

    set -l text ($reader 2>/dev/null | __unwrap_wrapped_text | string collect)
    test -z "$text"; and return 0

    commandline --insert -- $text
end
