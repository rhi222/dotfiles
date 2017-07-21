"" dein.vim settings {{{
" $B%W%i%0%$%s$,<B:]$K%$%s%9%H!<%k$5$l$k%G%#%l%/%H%j(B
let s:dein_dir = expand('~/.cache/dein')
" dein.vim $BK\BN(B
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim'

" dein.vim $B$,$J$1$l$P(B github $B$+$iMn$H$7$F$/$k(B
if &runtimepath !~# '/dein.vim'
  if !isdirectory(s:dein_repo_dir)
    execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
  endif
  execute 'set runtimepath^=' . fnamemodify(s:dein_repo_dir, ':p')
endif

" $B@_Dj3+;O(B
if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir)

  " $B%W%i%0%$%s%j%9%H$r<}$a$?(B TOML $B%U%!%$%k(B
  " $BM=$a(B TOML $B%U%!%$%k!J8e=R!K$rMQ0U$7$F$*$/(B
  let g:rc_dir    = expand('~/.vim/dein')
  let s:toml      = g:rc_dir . '/dein.toml'
  let s:lazy_toml = g:rc_dir . '/dein_lazy.toml'

  " TOML $B$rFI$_9~$_!"%-%c%C%7%e$7$F$*$/(B
  call dein#load_toml(s:toml,      {'lazy': 0})
  call dein#load_toml(s:lazy_toml, {'lazy': 1})

  " forcia$B$N%W%i%0%$%s$rFI$_9~$`(B
  call dein#local("~/.vim/dein")

  " $B@_Dj=*N;(B
  call dein#end()
  call dein#save_state()
endif

" $B$b$7!"L$%$%s%9%H!<%k$b$N$b$N$,$"$C$?$i%$%s%9%H!<%k(B
if dein#check_install()
  call dein#install()
endif
"" }}}

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
"highlight CursorLine term=none ctermbg=242
"highlight CursorLine cterm=NONE ctermbg=darkred ctermfg=white guibg=darkred guifg=white
"highlight CursorLine cterm=NONE ctermbg=24
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

" filetype
augroup fileTypeIndent
	autocmd!
	autocmd BufNewFile,BufRead *.py setlocal tabstop=4 softtabstop=4 noexpandtab
	autocmd BufNewFile,BufRead *.rb setlocal tabstop=2 softtabstop=2 shiftwidth=2
	"autocmd BufNewFile,BufRead *.rb setlocal shiftwidth=2
augroup END

autocmd BufWritePost *.py call Flake8()

"------------------------------------
""" deoplete
"------------------------------------
" Use deoplete.
" https://github.com/Shougo/deoplete.nvim
"" deplete.nvim settings {{{
let g:deoplete#enable_at_startup = 1
let g:deoplete#auto_complete_delay = 0
let g:deoplete#auto_complete_start_length = 1
let g:deoplete#enable_camel_case = 0
let g:deoplete#enable_ignore_case = 0
let g:deoplete#enable_refresh_always = 0
let g:deoplete#enable_smart_case = 1
let g:deoplete#file#enable_buffer_path = 1
let g:deoplete#max_list = 10000
" deoplete tab-complete
inoremap <expr><tab> pumvisible() ? "\<c-n>" : "\<tab>"
"" }}
