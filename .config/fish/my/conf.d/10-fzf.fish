# fzf settings
#
# キーバインドの所有者に注意。Ctrl+R / Ctrl+T / Alt+C は fzf 標準のシェル統合が握っている。
# ~/.config/fish/functions/fish_user_key_bindings.fish の `fzf --fish | source` が
# conf.d より後に走り、fzf.fish プラグインの bind を上書きするため。
# プラグイン側で生き残るのは Alt+Ctrl+L / Alt+Ctrl+S / Alt+Ctrl+P / Ctrl+V。
fzf_configure_bindings --directory=\ct

# Ctrl+R の履歴一覧をコマンドだけにする。
#
# fzf 0.74 のヒストリウィジェットはタブ区切りで3列を作る。
#   1列目 = 人が読める日時（%F %a %T）/ 2列目 = エポック秒（%s）/ 3列目以降 = コマンド
# 既定が --with-nth=2.. なので、放っておくと 2列目のエポック秒から表示される。
#
# **--nth も揃えるのが要点。** 表示から消しても検索対象に残っていると、
# コマンドに含まれる数字を打ったときにエポックの数字列へ誤ヒットする。
# 確定時に挿入される値は --accept-nth=3.. で常にコマンドだけなので、ここは表示と検索の話。
#
# 日時を一時的に見たいときは fzf 側の Alt+T で 1,3.. → 3.. → 2.. と切り替わる。
set -gx FZF_CTRL_R_OPTS '--with-nth=3.. --nth=3..'
