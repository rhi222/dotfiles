# 折返しを畳む貼り付け（ctrl-o = one-line paste）
#
# 端末に出た「本来1行」のコマンドやURLをコピーすると改行が混入する。畳む処理は
# unwrap-paste / __unwrap_wrapped_text にあり、ここはキーの割り当てだけを決める。
#
# **ctrl-v は上書きしない。** 既定の fish_clipboard_paste は改行をそのまま貼るので、
# 複数行のスクリプトや heredoc を貼る用途がそのまま残る。畳むのは明示操作にする。
#
# **キーは ctrl-o。** 空いている ctrl は o と q だけで、q は端末のフロー制御と衝突する。
# 隣接する候補は既定で埋まっている（ctrl-v = fish_clipboard_paste、
# alt-v = edit_command_buffer）。alt 併用は Windows Terminal + herdr の構成で
# アプリまで届かないため候補にしない（.config/herdr/config.toml の [keys] に同じ前提）。
# 覚え方は one-line paste の o。
#
# **`stty -a` が `discard = ^O` を出すが、reader には届く。** ^O は termios の VDISCARD で
# iexten 有効時は tty ドライバが食う文字だが、それは fish が子プロセスへ戻すモードの話。
# fish の reader は同じく iexten 依存の VLNEXT(^V) を fish_clipboard_paste に割り当てて
# 実際に動かしているので、^O も同様に reader 側が受け取る。
#
# bind は conf.d から張る。fish_user_key_bindings は追跡外ファイルの影を作るための
# 空定義なので中身を増やさない（my/functions/fish_user_key_bindings.fish 参照）。
if status is-interactive
    bind ctrl-o unwrap-paste
    # vi バインドへ切り替えた場合も同じキーで効かせる。vi 未使用でもエラーにはならない
    bind -M insert ctrl-o unwrap-paste
end
