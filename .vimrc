"" dein.vim settings {{{
" dein自体の自動インストール
let s:dein_dir = expand('~/.cache/dein')
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim'
if &runtimepath !~# '/dein.vim'
	if !isdirectory(s:dein_repo_dir)
		execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
	endif
	execute 'set runtimepath^=' . fnamemodify(s:dein_repo_dir, ':p')
endif

" プラグイン読み込み＆キャッシュ作成
if dein#load_state(s:dein_dir)
	call dein#begin(s:dein_dir)
	let g:rc_dir    = expand('~/.vim/dein')
	let s:toml      = g:rc_dir . '/dein.toml'
	"let s:lazy_toml = g:rc_dir . '/dein_lazy.toml'
	call dein#load_toml(s:toml,      {'lazy': 0})
	"call dein#load_toml(s:lazy_toml, {'lazy': 1})
	call dein#end()
	call dein#save_state()
endif

" 不足プラグインの自動インストール
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

" ビジュアルモードで選択したテキストが、クリップボードに入るようにする
" http://nanasi.jp/articles/howto/editing/clipboard.html
" 無名レジスタに入るデータを、*レジスタにも入れる。
" http://stackoverflow.com/questions/39645253/clipboard-failure-in-tmux-vim-after-upgrading-to-macos-sierra
"set clipboard=unnamedplus,autoselect
"set clipboard+=unnamed
"set clipboard=unnamedplus
set clipboard=unnamed

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 1
syntax on

" encoding
set fileencodings=utf-8,iso-2022-jp,cp932,sjis,euc-jp
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

" filetype
augroup fileTypeIndent
	autocmd!
	autocmd BufNewFile,BufRead *.py setlocal tabstop=4 softtabstop=4 shiftwidth=4
	autocmd BufNewFile,BufRead *.rb setlocal tabstop=2 softtabstop=2 shiftwidth=2
augroup END

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
inoremap <expr><tab> pumvisible() ? "\<C-n>" :
      \ neosnippet#expandable_or_jumpable() ?
      \    "\<Plug>(neosnippet_expand_or_jump)" : "\<tab>"
"" }}
