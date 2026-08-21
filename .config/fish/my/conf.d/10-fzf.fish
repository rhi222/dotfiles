# fzf settings
#
# キーバインドは fzf.fish プラグインが持つ。fzf 標準のシェル統合（`fzf --fish | source`）は
# `my/functions/fish_user_key_bindings.fish` の空定義で塞いであるので、
# `FZF_CTRL_R_OPTS` などの標準側の環境変数は効かない。
# プラグイン側の設定変数（`fzf_history_opts` など）を使うこと。
#
# **「入っていないから効かない」ではなく「入らないようにしている」。** 昔の
# `~/.fzf/install` が置く追跡外の `fish_user_key_bindings.fish` の有無で担当が端末ごとに
# 割れ、担当が変われば読む変数も変わるため、下の設定が端末をまたぐたび無効化されていた。
#
# **プラグインの有無を見てから呼ぶ。** fzf.fish は fisher 管理で、その宣言（fish_plugins）は
# 追跡していない。新環境ではリンクだけ先に張られるので、素で呼ぶと毎回の起動で
# command not found が出る。
if type -q fzf_configure_bindings
    fzf_configure_bindings --directory=\ct
end

# Ctrl+R（_fzf_search_history）の一覧をコマンドだけにする。
#
# 行の形は "MM-DD HH:MM:SS │ <command>"。
#
# **`fzf_history_time_format` を空にしても消えない。** _fzf_search_history が
# `--show-time="$fzf_history_time_format │ "` と組み立てるため、空にすると
# 先頭に " │ " だけが残る。そこで時刻の生成ではなく fzf の表示側で落とす。
#
# **--nth は付けない。** --nth は --with-nth を適用した後の文字列に対して効くので、
# 重ねると2列目が存在しなくなり、コマンド名でさえ検索に引っかからなくなる。
# --with-nth だけで表示と検索対象の両方が絞られる（"18" が "08-18 ..." に
# 誤ヒットしないことを確認済み）。
#
# 確定時に挿入される値と preview は、プラグイン側が `^.*? │ ` を剥がすので影響しない。
set -g fzf_history_opts --delimiter=' │ ' --with-nth='2..'
