if has('vim_starting')
	set runtimepath+=~/.vim/bundle/neobundle.vim/
endif

call neobundle#begin(expand('~/.vim/bundle/'))
NeoBundleFetch 'Shougo/neobundle.vim'
NeoBundle 'scrooloose/nerdtree'
NeoBundle 'ctrlpvim/ctrlp.vim'
"NeoBundle 'jiangmiao/auto-pairs'
"NeoBundle 'junegunn/vim-easy-align'
"NeoBundle 'Shougo/neocomplcache'
NeoBundle 'Yggdroot/indentLine'
NeoBundle 'forcia'
NeoBundle 'mattn/emmet-vim'
NeoBundle 't9md/vim-quickhl'
"NeoBundle 'Shougo/neocomplete.vim'
call neobundle#end()

" setting statusline
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
set statusline=%<%f\ %m%r%h%w
set statusline+=%{'['.(&fenc!=''?&fenc:&enc).']['.&fileformat.']'}
set statusline+=%=%l/%L,%c%V%8P
set laststatus=2

" ignore upper or lower case
set ignorecase

" ビジュアルモードで選択したテキストが、クリップボードに入るようにする
" http://nanasi.jp/articles/howto/editing/clipboard.html
" 無名レジスタに入るデータを、*レジスタにも入れる。
set clipboard=unnamedplus,autoselect
"set clipboard+=unnamed
"set clipboard=unnamedplus

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 1

" encoding
set fileencodings=iso-2022-jp,cp932,sjis,euc-jp,utf-8
set encoding=utf-8

" etc
set tabstop=4
set hlsearch
set number
set cursorline
set incsearch
let g:indentLine_char = '|'
set list listchars=trail:~,tab:\|\ 
hi SpecialKey guibg=NONE guifg=Gray40


"------------------------------------
""" vim-quickhl
"------------------------------------
nmap <Space>m <Plug>(quickhl-toggle)
xmap <Space>m <Plug>(quickhl-toggle)
nmap <Space>M <Plug>(quickhl-reset)
xmap <Space>M <Plug>(quickhl-reset)
nmap <Space>j <Plug>(quickhl-match)

" ファイルの拡張子を判定する
" http://d.hatena.ne.jp/wiredool/20120618/1340019962
filetype plugin indent on
