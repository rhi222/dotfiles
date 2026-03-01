# PATH settings
# path設定はfish_add_pathを利用
# https://zenn.dev/estra/articles/zenn-fish-add-path-final-answer

# go install でインストールしたバイナリ用（Go自体はmiseで管理）
fish_add_path $HOME/go/bin

# pipx等が使う共通バイナリディレクトリ
fish_add_path $HOME/.local/bin

# for win32yank
# https://qiita.com/v2okimochi/items/f53edcf79a4b71f519b1#%E3%83%9E%E3%82%A6%E3%82%B9%E6%93%8D%E4%BD%9C%E3%82%84%E3%82%AF%E3%83%AA%E3%83%83%E3%83%97%E3%83%9C%E3%83%BC%E3%83%89%E5%85%B1%E6%9C%89%E3%82%92%E8%A8%AD%E5%AE%9A%E3%81%99%E3%82%8B
fish_add_path $HOME/bin

# docker setting
# https://qiita.com/v2okimochi/items/f53edcf79a4b71f519b1#wsl2%E3%81%AEpath%E3%81%8B%E3%82%89windows%E3%83%91%E3%82%B9%E3%82%92%E6%8A%9C%E3%81%8F
fish_add_path /mnt/c/Program\ Files/Docker/Docker/resources/bin
