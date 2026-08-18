# fzf settings
#
# キーバインドは fzf.fish プラグインが持つ。fzf 標準のシェル統合（`fzf --fish | source`）は
# 有効化していないので、`FZF_CTRL_R_OPTS` などの標準側の環境変数は効かない。
# プラグイン側の設定変数（`fzf_history_opts` など）を使うこと。
fzf_configure_bindings --directory=\ct

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
