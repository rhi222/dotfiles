# yazi shell integration
#
# `y` で起動し、終了時のディレクトリへ自動 cd する公式パターン。
# https://yazi-rs.github.io/docs/quick-start
function y
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    command yazi $argv --cwd-file="$tmp"
    if read -z cwd <"$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]; and test -d "$cwd"
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
end
