# ディレクトリ構成
myというディレクトリを切っているのは、なるべく他のプラグインと名前空間をかぶらないようにするため

myプレフィックスがない場合、たとえばcmp.luaという設定ファイルがあるとcmpプラグインと名前空間が被ってしまいrequire('cmp')はパスで見つけたファイルを優先してimportしてしまうから

## 参考
- https://zenn.dev/vim_jp/articles/2024-02-11-vim-update-my-init-lua

# keymap

## 目的
- 数が増えてきたので、覚えやすさを重視して再考

## 方針
- 打ちやすい
	- タイプ数が少ない
- 覚えやすい
	- 理屈付け
	- prefixで統一されている
- 副作用が少ない
	- nvimのデフォルトキーマップの上書きは限定的にしたい

## prefixの候補
- Ctrl: 推奨? だいぶデフォルトで使っている
- Space: 推奨
- [: ジャンプ系推奨だが比較的空いてる
- ]: ジャンプ系推奨だが比較的空いてる
- g: 比較的空いてる
- z: 表示位置調整系に使うのが良い

## memo
### 候補

- <C-e> 
- <C-q>
- <C-y>
- <C-p>
- <C-c>
- <C-n>

### mode
優先的に考える
- n
- v (x,s)
- i

頻度少ないので低優先
- c
- o
- t
- l

### 案
- 使えそうなキーマップを列挙して、その範囲の中で理屈をつけていく
- 一軍: Ctrl
- code jump: g
- fold: z
- 覚えやすさ優先: <Space> prefix
	- insertモードで発動しにくいか

### 列挙
- copilot
	- space c prefix
- C-p
	- fzf files
- C-g
	- fzf grep

	
## 参考
- https://zenn.dev/vim_jp/articles/2023-05-19-vim-keybind-philosophy
- https://zenn.dev/nil2/articles/802f115673b9ba
- https://maku77.github.io/vim/keymap/current-map.html
- https://stackoverflow.com/questions/2239226/saving-output-of-map-in-vim


