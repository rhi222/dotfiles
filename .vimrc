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

" $B%S%8%e%"%k%b!<%I$GA*Br$7$?%F%-%9%H$,!"%/%j%C%W%\!<%I$KF~$k$h$&$K$9$k(B
" http://nanasi.jp/articles/howto/editing/clipboard.html
" $BL5L>%l%8%9%?$KF~$k%G!<%?$r!"(B*$B%l%8%9%?$K$bF~$l$k!#(B
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

" $B%U%!%$%k$N3HD%;R$rH=Dj$9$k(B
" http://d.hatena.ne.jp/wiredool/20120618/1340019962
filetype plugin indent on
