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
  let g:rc_dir    = expand('~/.config/nvim/dein')
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

"------------------------------------
""" general
"------------------------------------
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
set clipboard+=unnamedplus

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 1

" encoding
" set fileencodings=iso-2022-jp,cp932,sjis,euc-jp,utf-8
set fileencodings=utf-8,iso-2022-jp,cp932,sjis,euc-jp
"set encoding=utf-8

" tab
set tabpagemax=50

" etc
set tabstop=4
set shiftwidth=4
set hlsearch
set number
" set cursorline
" highlight CursorLine cterm=NONE ctermbg=Black
" highlight CursorLine gui=NONE guibg=Black
set incsearch
hi SpecialKey guibg=NONE guifg=Gray40
set list listchars=trail:~,tab:\|\ 

" mouse
set mouse=a

" reload
" nmap <silent> <C-w>r <Plug>(ale_next_wrap)

"------------------------------------
""" vim-quickhl
"------------------------------------
nmap <Space>m <Plug>(quickhl-toggle)
xmap <Space>m <Plug>(quickhl-toggle)
nmap <Space>M <Plug>(quickhl-reset)
xmap <Space>M <Plug>(quickhl-reset)
nmap <Space>j <Plug>(quickhl-match)


"------------------------------------
""" filetype settings
"------------------------------------
" ファイルの拡張子を判定する
" http://d.hatena.ne.jp/wiredool/20120618/1340019962
filetype plugin indent on

" filetype
augroup fileTypeIndent
	autocmd!
	"autocmd BufNewFile,BufRead *.py setlocal tabstop=4 softtabstop=4 noexpandtab
	autocmd BufNewFile,BufRead *.py setlocal tabstop=4 softtabstop=4 expandtab
	autocmd BufNewFile,BufRead *.ts setlocal tabstop=4 softtabstop=4 expandtab
	autocmd BufNewFile,BufRead *.rb setlocal expandtab tabstop=2 softtabstop=2 shiftwidth=2
	autocmd BufNewFile,BufRead *.yml setlocal expandtab tabstop=2 softtabstop=2 shiftwidth=2
augroup END

autocmd BufWritePost *.py call Flake8()
	"autocmd BufNewFile,BufRead *.py setlocal tabstop=4 softtabstop=4 expandtab

"------------------------------------
""" deoplete
"------------------------------------
" Use deoplete.
" https://github.com/Shougo/deoplete.nvim
"-- deplete.nvim settings {{{
" standard settings
let g:deoplete#enable_at_startup = 1
let g:deoplete#enable_smart_case = 1
let g:deoplete#auto_complete_delay = 0
let g:deoplete#auto_complete_start_length = 1
let g:deoplete#enable_camel_case = 0
let g:deoplete#enable_ignore_case = 1
let g:deoplete#enable_refresh_always = 0
let g:deoplete#file#enable_buffer_path = 1
let g:deoplete#max_list = 10000
" https://github.com/Shougo/deoplete.nvim/issues/298
set completeopt-=preview
" set sources
let g:deoplete#sources = {}
" 5MB
let deoplete#tag#cache_limit_size = 5000000
" deoplete tab-complete
inoremap <expr><tab> pumvisible() ? "\<c-n>" : "\<tab>"
"-- }}}

"------------------------------------
""" vim-jsdoc
"------------------------------------
" https://github.com/heavenshell/vim-jsdoc
 nmap <silent> <C-l> <Plug>(jsdoc)
let g:jsdoc_enable_es6 = 0
" nmap <silent> <C-l> ?function<cr>:noh<cr><Plug>(jsdoc)


" jq
" http://qiita.com/tekkoc/items/324d736f68b0f27680b8
command! -nargs=? Jq call s:Jq(<f-args>)
function! s:Jq(...)
    if 0 == a:0
        let l:arg = "."
    else
        let l:arg = a:1
    endif
    execute "%! jq \"" . l:arg . "\""
endfunction

"------------------------------------
""" neosnippet
"------------------------------------
"" Plugin key-mappings.
" Note: It must be "imap" and "smap".  It uses <Plug> mappings.
imap <C-k>     <Plug>(neosnippet_expand_or_jump)
smap <C-k>     <Plug>(neosnippet_expand_or_jump)
xmap <C-k>     <Plug>(neosnippet_expand_target)

" SuperTab like snippets behavior.
" Note: It must be "imap" and "smap".  It uses <Plug> mappings.
imap <C-k>     <Plug>(neosnippet_expand_or_jump)
"imap <expr><TAB>
" \ pumvisible() ? "\<C-n>" :
" \ neosnippet#expandable_or_jumpable() ?
" \    "\<Plug>(neosnippet_expand_or_jump)" : "\<TAB>"
smap <expr><TAB> neosnippet#expandable_or_jumpable() ?
\ "\<Plug>(neosnippet_expand_or_jump)" : "\<TAB>"

" For conceal markers.
if has('conceal')
  set conceallevel=2 concealcursor=niv
endif

" 自分用 snippet ファイルの場所 (任意のパス)
let g:neosnippet#snippets_directory = '~/.vim/snippets/'

"------------------------------------
""" FZF
"------------------------------------
" init.vim
function! s:find_git_root()
  return system('git rev-parse --show-toplevel 2> /dev/null')[:-2]
endfunction

command! ProjectFiles execute 'Files' s:find_git_root()

nnoremap <silent> <C-p> :ProjectFiles<CR>
nnoremap <silent> <M-p> :History<CR>
" https://wonderwall.hatenablog.com/entry/2017/10/07/220000
let g:fzf_layout = { 'down': '~90%' }


"------------------------------------
""" apache config file
"------------------------------------
autocmd BufNewFile,BufRead .htaccess setfiletype apache
autocmd BufNewFile,BufRead httpd* setfiletype apache

"------------------------------------
" ale　実行タイミング
" https://rcmdnk.com/blog/2017/09/25/computer-vim/
"------------------------------------
let g:ale_lint_on_enter = 1
let g:ale_lint_on_save =1
let g:ale_lint_on_text_changed = 1
let g:ale_lint_on_insert_leave = 0

"------------------------------------
""" eslint quickrun
" https://qiita.com/zaki-yama/items/6bcc24469d06acdf8643
"------------------------------------
call dein#add('w0rp/ale')
let g:ale_statusline_format = ['⨉ %d', '⚠ %d', '⬥ ok']
let g:ale_linters = {
\   'javascript': ['eslint', 'flow'],
\   'html': ['write-good', 'alex!!', 'proselint'],
\   'typescript': ['eslint', 'tsserver', 'typecheck'],
\}
let g:ale_set_loclist = 0
let g:ale_set_quickfix = 1

"------------------------------------
""" lightline.vim
" https://github.com/itchyny/lightline.vim
"------------------------------------
call dein#add('itchyny/lightline.vim')
let g:lightline = {
  \'active': {
  \  'left': [
  \    ['mode', 'paste'],
  \    ['readonly', 'relativepath', 'modified'],
  \    ['ale'],
  \  ]
  \},
  \'component_function': {
  \  'ale': 'ALEStatus'
  \}
\ }

function! LightLineFilename()
  return expand('%:p:h')
endfunction

highlight ALEError ctermfg=235 ctermbg=208 guifg=#262626 guibg=#ff8700
highlight ALEWarning ctermfg=117 ctermbg=24 guifg=#87dfff guibg=#005f87


nmap <silent> <C-w>n <Plug>(ale_next_wrap)
nmap <silent> <C-w>p <Plug>(ale_previous_wrap)


"------------------------------------
""" ack.vim
" https://github.com/mileszs/ack.vim
"------------------------------------
if executable('rg')
  let g:ackprg = 'rg --vimgrep'
endif

"------------------------------------
""" nerdcommenter
" https://github.com/scrooloose/nerdcommenter
"------------------------------------
let g:NERDSpaceDelims=1
let g:NERDDefaultAlign='left'


"------------------------------------
""" dbext.vim
" https://github.com/vim-scripts/dbext.vim
" http://www.jonathansacramento.com/posts/20160122-improve-postgresql-workflow-vim-dbext.html
"------------------------------------
"let g:dbext_default_profile_postgres = 'type=PGSQL:host=localhost:user=forcia:dbname=dom_tour:passwd=forcia:port=9999'
"let g:dbext_default_profile_psql = 'type=PGSQL:host=localhost:port=9990:dbname=dom_tour:user=forcia:passwd=forcia'
"let g:dbext_default_profile = 'psql'
"
""--- LXTerminal
set guicursor=

"------------------------------------
""" denite
" https://github.com/Shougo/denite.nvim
"------------------------------------
if executable('rg')
  call denite#custom#var('file_rec', 'command',
        \ ['rg', '--files', '--glob', '!.git'])
  call denite#custom#var('grep', 'command', ['rg'])
endif

" promptの変更
call denite#custom#option('default', 'prompt', '>')
" key bind
" denite/insert モードのときは，C- で移動できるようにする
call denite#custom#map('insert', "<C-j>", '<denite:move_to_next_line>')
call denite#custom#map('insert', "<C-k>", '<denite:move_to_previous_line>')

" jj で denite/insert を抜けるようにする
call denite#custom#map('insert', 'jj', '<denite:enter_mode:normal>')

" tabopen や vsplit のキーバインドを割り当て
call denite#custom#map('insert', "<C-t>", '<denite:do_action:tabopen>')
call denite#custom#map('insert', "<C-v>", '<denite:do_action:vsplit>')
call denite#custom#map('normal', "v", '<denite:do_action:vsplit>')


" ファイル内検索
" カーソル以下の単語をgrep
nnoremap <silent> ;cg :<C-u>DeniteCursorWord grep -buffer-name=search line<CR><C-R><C-W><CR>
" search
nnoremap <silent> / :<C-u>Denite -buffer-name=search -auto-resize line<CR>

" 横断検索
" 普通にgrep
nnoremap <silent> ;g :<C-u>Denite -buffer-name=search -mode=normal grep<CR>

" ctrlp
"nnoremap <silent> <C-p> :<C-u>Denite file_rec<CR>

" resume previous buffer
nnoremap <silent> ;r :<C-u>Denite -buffer-name=search -resume -mode=normal<CR>
