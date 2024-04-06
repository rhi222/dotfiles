myというディレクトリを切っているのは、なるべく他のプラグインと名前空間をかぶらないようにするため

myプレフィックスがない場合、たとえばcmp.luaという設定ファイルがあるとcmpプラグインと名前空間が被ってしまいrequire('cmp')はパスで見つけたファイルを優先してimportしてしまうから

https://zenn.dev/vim_jp/articles/2024-02-11-vim-update-my-init-lua
