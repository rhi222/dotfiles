# scripts/db/tunnel.sh の app / env を接続先表から補完する。
#
# **completions/ ではなく conf.d に置く。** fish は補完をコマンド名で autoload する
# ので、`bash ~/scripts/db/tunnel.sh` の形へ効かせるには `complete -c bash` の定義が
# 起動時に読まれている必要がある。これを completions/bash.fish に置くと fish 同梱の
# bash 補完を丸ごと隠すため、conf.d で両方まとめて登録する。
#
# 直接実行（`~/scripts/db/tunnel.sh`）にも効く。fish は path 付きでも basename で
# 補完を引くので、`complete -c tunnel.sh` がそのまま当たる。
#
# 候補は tunnel.sh 自身と同じ接続先表から引く。表を増やせば補完も追随し、
# app / env の一覧をここへ二重に持たない。

function __tunnel_sh_config --description 'tunnel.sh の接続先表のパス'
    if set -q SSH_TUNNEL_CONFIG
        echo $SSH_TUNNEL_CONFIG
    else if set -q XDG_CONFIG_HOME
        echo $XDG_CONFIG_HOME/dotfiles/ssh-tunnel.tsv
    else
        echo $HOME/.config/dotfiles/ssh-tunnel.tsv
    end
end

function __tunnel_sh_rows --description 接続先表のコメントと空行を除いた行
    set -l conf (__tunnel_sh_config)
    test -f $conf; or return 0
    grep -v '^[[:space:]]*\(#\|$\)' $conf
end

# tunnel.sh へ渡された引数だけを返す。`bash <path>/tunnel.sh` の2トークンを落とす。
function __tunnel_sh_args
    set -l tokens (commandline -opc)
    if test "$tokens[1]" = bash
        set tokens $tokens[3..]
    else
        set tokens $tokens[2..]
    end
    # **printf '%s\n' で流さない。** 引数が空のとき printf は空行を1行出すので、
    # count が 0 にならず app 位置（1つ目）の補完が発火しなかった。
    for token in $tokens
        echo $token
    end
end

# 補完位置。1ならapp、2ならenv、3ならオプション。
function __tunnel_sh_at
    test (count (__tunnel_sh_args)) -eq (math $argv[1] - 1)
end

# `bash` の補完を乗っ取らないよう、2つ目のトークンが tunnel.sh のときだけ真にする。
function __tunnel_sh_invoked
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2; or return 1
    string match -qr '(^|/)tunnel\.sh$' -- $tokens[2]
end

function __tunnel_sh_apps
    __tunnel_sh_rows | awk '!seen[$1]++ { print $1 }'
end

function __tunnel_sh_envs
    set -l args (__tunnel_sh_args)
    __tunnel_sh_rows | awk -v a="$args[1]" '$1 == a { print $2 "\tlocalhost:" $4 " -> " $5 }'
end

for cmd in tunnel.sh bash
    # bash 側は tunnel.sh を起動する行に限る。tunnel.sh 側は常に真。
    set -l guard true
    test $cmd = bash; and set guard __tunnel_sh_invoked

    complete -c $cmd -f -n "$guard; and __tunnel_sh_at 1" -a '(__tunnel_sh_apps)' -d 対象アプリ
    complete -c $cmd -f -n "$guard; and __tunnel_sh_at 2" -a '(__tunnel_sh_envs)'
    complete -c $cmd -f -n "$guard; and __tunnel_sh_at 3" -a --read-only -d 読み取り専用エンドポイントへ繋ぐ
end
