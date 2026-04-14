# fzf settings
#
# キーバインド: PatrickF1/fzf.fish のデフォルトを上書き
#   Ctrl+T → ディレクトリ/ファイル検索（デフォルトは Alt+Ctrl+F）
fzf_configure_bindings --directory=\ct
#
# Ctrl+R の履歴検索は fzf.fish プラグイン（PatrickF1/fzf.fish）の
# _fzf_search_history が担当する。タイムスタンプ列を非表示にするため
# fzf_history_time_format を空文字で上書きする（区切り棒 │ は残る）。
set -gx fzf_history_time_format ''
