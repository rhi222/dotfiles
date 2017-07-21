"" dein.vim settings {{{
" プラグインが実際にインストールされるディレクトリ
let s:dein_dir = expand('~/.cache/dein')
" dein.vim 本体
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim'

" dein.vim がなければ github から落としてくる
if &runtimepath !~# '/dein.vim'
  if !isdirectory(s:dein_repo_dir)
    execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
  endif
  execute 'set runtimepath^=' . fnamemodify(s:dein_repo_dir, ':p')
endif

" 設定開始
if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir)

  " プラグインリストを収めた TOML ファイル
  " 予め TOML ファイル（後述）を用意しておく
  let g:rc_dir    = expand('~/.vim/dein')
  let s:toml      = g:rc_dir . '/dein.toml'
  let s:lazy_toml = g:rc_dir . '/dein_lazy.toml'

  " TOML を読み込み、キャッシュしておく
  call dein#load_toml(s:toml,      {'lazy': 0})
  call dein#load_toml(s:lazy_toml, {'lazy': 1})

  " forciaのプラグインを読み込む
  call dein#local("~/.vim/dein")

  " 設定終了
  call dein#end()
  call dein#save_state()
endif

" もし、未インストールものものがあったらインストール
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


" ファイルの拡張子を判定する
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
