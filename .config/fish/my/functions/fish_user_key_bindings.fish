# キーバインドの拡張点を repo 側で握るための空定義。
#
# **消さないこと。中身が空なのが仕事。**
#
# 昔の `~/.fzf/install` は `~/.config/fish/functions/fish_user_key_bindings.fish` に
# `fzf --fish | source` の1行を置いていく。これは追跡外の実ファイルなので端末ごとに
# 有る／無いが分かれ、有る端末では fzf 標準のシェル統合が conf.d より後に走って
# fzf.fish の bind を上書きする（Ctrl+R / Ctrl+T / Alt+C）。
#
# Ctrl+R は担当が変わると設定変数まで変わるため、これが端末差の実害になる。
#   fzf.fish の _fzf_search_history  → `fzf_history_opts` / 区切りは " │ "
#   fzf 標準の fzf-history-widget    → `FZF_CTRL_R_OPTS`  / 区切りはタブ3列
# 片方に寄せた設定はもう片方では丸ごと効かないので、履歴一覧の時刻列を消す修正が
# 端末をまたぐたびに元へ戻る（実際に2回往復している）。
#
# `config.fish` が `my/functions` を `fish_function_path` の先頭に置くので、
# ここに同名の定義があれば追跡外のファイルは autoload されず影になる。
# 担当は `10-fzf.fish` が宣言するとおり fzf.fish 側に固定される。
#
# 手で消して回る運用にしないのは、消しても `~/.fzf/install` を踏めば復活するため。
function fish_user_key_bindings
end
