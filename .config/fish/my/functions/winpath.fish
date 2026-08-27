# WSLのパスを、host側のファイルエクスプローラーへ貼れる表記へ変換する
#
#   winpath                    # カレントディレクトリ
#   winpath docs/ README.md    # 複数指定は1行ずつ
#   winpath -c docs/           # clipboardへも入れる
#
# 変換そのものは `wslpath -w` に委譲する。`/mnt/c/...` を `C:\...` へ、それ以外を
# `\\wsl.localhost\<distro>\...` へ振り分けるのも、相対パスをCWD基準で解決するのも
# wslpath の挙動をそのまま使う。distro名を自前で組み立てない。
#
# **wslpath は symlink を実体へ解決する。** dotfiles配下は ~/.config/fish のように
# symlinkが多いが、Explorer は WSL の symlink を辿れないことがある。実体パスを返す
# この挙動の方が、貼り付け先で確実に開ける。
#
# 非WSLの判定は `wslpath` の有無だけで足りる。wslpath はWSL内にしか存在せず、
# WSL_DISTRO_NAME はsudoやcron経由で落ちることがあるので、環境変数より信頼できる。
function winpath --description 'WSLのパスをWindows側の表記へ変換する（-c でclipboardへ）'
    argparse c/copy -- $argv
    or return 2

    if not type -q wslpath
        echo "winpath: WSL環境ではないため変換できません（wslpath が見つかりません）" >&2
        return 1
    end

    set -l targets $argv
    if test (count $targets) -eq 0
        set targets .
    end

    set -l results
    set -l failed 0

    for target in $targets
        # 存在しないパスでも変換結果は返す。まだ作っていないファイルの置き場を
        # Explorerへ貼りたいことがあるため、警告だけ出して打ち切らない。
        if not test -e "$target"
            echo "winpath: 存在しないパス: $target" >&2
        end

        # wslpath自身のメッセージは捨て、どの引数で失敗したかを名指しする。
        set -l converted (wslpath -w "$target" 2>/dev/null)
        set -l rc $status
        if test $rc -ne 0; or test -z "$converted"
            echo "winpath: 変換に失敗しました: $target" >&2
            set failed 1
            continue
        end

        set -a results $converted
        echo $converted
    end

    if not set -q _flag_copy
        return $failed
    end

    if test (count $results) -eq 0
        echo "winpath: コピーする変換結果がありません" >&2
        return 1
    end

    # nvim・tmux と同じ経路に揃える。win32yank は bootstrap の管理外で新環境では
    # 未導入のことがあるため、WSLなら必ずある clip.exe へ落とす。
    set -l clipper
    if type -q win32yank.exe
        set clipper win32yank.exe -i --crlf
    else if type -q clip.exe
        set clipper clip.exe
    else
        echo "winpath: clipboard コマンドが見つかりません（win32yank.exe / clip.exe）" >&2
        return 1
    end

    # **末尾改行を付けない。** Explorerのアドレスバーへ貼ったとき、改行がEnterとして
    # 食われて意図しない遷移が起きる。そのため echo ではなく printf '%s' を使う。
    # `string collect` を通さないと、コマンド置換が改行で分割してリストにしてしまい、
    # 引用して渡した時点で改行が空白へ潰れる。
    set -l payload (string join \n -- $results | string collect)
    if not printf '%s' "$payload" | $clipper
        echo "winpath: clipboardへの書き込みに失敗しました" >&2
        return 1
    end

    # stdout はパイプで使える状態に保ち、確認用の1行は stderr へ出す。
    echo "winpath: copied to clipboard" >&2
    return $failed
end
