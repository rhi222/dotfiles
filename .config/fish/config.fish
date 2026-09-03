# Add my functions directory to fish_function_path
#
# conf.d を source する前に設定する。conf.d の中から my/functions の関数を呼ぶと、
# 後から追加していた場合は autoload に失敗して fish_command_not_found が走る
# （mise hook-not-found と /usr/lib/command-not-found で実測 380ms を浪費し、
# しかも当該処理は黙って何もしないまま終わる）。
set -g fish_function_path ~/.config/fish/my/functions $fish_function_path

# Add my completions directory to fish_complete_path
set -g fish_complete_path ~/.config/fish/my/completions $fish_complete_path

# Load my custom configurations in order
for file in ~/.config/fish/my/conf.d/*.fish
    if test -r $file
        source $file
    end
end

# **conf.d を全部読んだ後に呼ぶ。** 99-local.fish の閾値・除外リストを見てから
# 判定させる必要がある。**docker の有無は関数側で見る。** 未導入の端末では
# docker info が command not found ハンドラを起こし、起動のたびに snap の
# 導入案内が出る。
if functions -q __docker_clean_greeting
    __docker_clean_greeting
end

# Generated for envman. Do not edit.
test -s ~/.config/envman/load.fish; and source ~/.config/envman/load.fish
