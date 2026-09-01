# dclean のオプション。実体は dotctl docker clean（と --refresh だけ docker refresh）。
# 引数はフラグのみでファイルを取らないので -f でファイル補完を止める。
complete -c dclean -f
complete -c dclean -f -s a -l all -d '重掃除（未使用イメージとビルドキャッシュも消す）'
complete -c dclean -f -l status -d 掃除せず溜まり具合だけ表示
complete -c dclean -f -l refresh -d 'キャッシュだけ更新（掃除しない）'
complete -c dclean -f -s h -l help -d 使い方を表示
