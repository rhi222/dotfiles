" ----------- dein.vim settings {{{
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
" }}} -------------------------

" ----------- general settings {{{
" setting statusline
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
set statusline=%<%f\ %m%r%h%w
set statusline+=%{'['.(&fenc!=''?&fenc:&enc).']['.&fileformat.']'}
set statusline+=%=%l/%L,%c%V%8P
set laststatus=2


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

" etc
set tabpagemax=50
set tabstop=4
set shiftwidth=4
set hlsearch
set number
set incsearch
" ignore upper or lower case
set ignorecase
hi SpecialKey guibg=NONE guifg=Gray40
set list listchars=trail:~,tab:\|\ 

" highlight
highlight Normal ctermbg=NONE guibg=NONE
highlight NonText ctermbg=NONE guibg=NONE
highlight SpecialKey ctermbg=NONE guibg=NONE
highlight EndOfBuffer ctermbg=NONE guibg=NONE

" mouse
set mouse=a

" reload
" nmap <silent> <C-w>r <Plug>(ale_next_wrap)

" }}} -------------------------


" ----------- vim-quickhl settings {{{
nmap <Space>m <Plug>(quickhl-toggle)
xmap <Space>m <Plug>(quickhl-toggle)
nmap <Space>M <Plug>(quickhl-reset)
xmap <Space>M <Plug>(quickhl-reset)
nmap <Space>j <Plug>(quickhl-match)
" }}} -------------------------


" ----------- filetype settings {{{
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
	autocmd BufNewFile,BufRead *.yaml setlocal expandtab tabstop=2 softtabstop=2 shiftwidth=2
	autocmd BufNewFile,BufRead .htaccess setfiletype apache
	autocmd BufNewFile,BufRead httpd* setfiletype apache
augroup END

autocmd BufWritePost *.py call Flake8()
	"autocmd BufNewFile,BufRead *.py setlocal tabstop=4 softtabstop=4 expandtab
" }}} -------------------------


" ----------- deoplete.nvim settings {{{
" https://github.com/Shougo/deoplete.nvim
" standard settings
let g:deoplete#enable_at_startup = 1
" https://github.com/Shougo/deoplete.nvim/issues/298
set completeopt-=preview
" set sources
let g:deoplete#sources = {}
" deoplete tab-complete
inoremap <expr><tab> pumvisible() ? "\<c-n>" : "\<tab>"
" }}} -------------------------


" ----------- vim-jsdoc settings {{{
" https://github.com/heavenshell/vim-jsdoc
 nmap <silent> <C-l> <Plug>(jsdoc)
let g:jsdoc_enable_es6 = 0
" nmap <silent> <C-l> ?function<cr>:noh<cr><Plug>(jsdoc)
" }}} -------------------------


" ----------- jq settings {{{
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
" }}} -------------------------


" -----------neosnippet settings {{{
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
" }}} -------------------------


" ----------- FZF settings {{{
" init.vim
function! s:find_git_root()
  return system('git rev-parse --show-toplevel 2> /dev/null')[:-2]
endfunction

command! ProjectFiles execute 'Files' s:find_git_root()

"nnoremap <silent> <C-p> :ProjectFiles<CR>
nnoremap <silent> <M-p> :History<CR>
" https://wonderwall.hatenablog.com/entry/2017/10/07/220000
let g:fzf_layout = { 'down': '~90%' }
" }}} -------------------------


" ----------- ale settings {{{
" https://rcmdnk.com/blog/2017/09/25/computer-vim/
call dein#add('w0rp/ale')
let g:ale_lint_on_enter = 0
let g:ale_lint_on_save =1
let g:ale_lint_on_text_changed = 0
let g:ale_lint_on_insert_leave = 0
" eslint quickrun
" https://qiita.com/zaki-yama/items/6bcc24469d06acdf8643
let g:ale_statusline_format = ['⨉ %d', '⚠ %d', '⬥ ok']
let g:ale_linters = {
\   'javascript': ['eslint', 'flow'],
\   'html': ['write-good', 'alex!!', 'proselint'],
\   'typescript': ['eslint', 'tsserver', 'typecheck'],
\   'python': ['flake8'],
\}
let g:ale_set_loclist = 0
let g:ale_set_quickfix = 1
" }}} -------------------------


" ----------- lightline.vim settings {{{
" https://github.com/itchyny/lightline.vim
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
" }}} -------------------------


" ----------- ack.vim settings {{{
" https://github.com/mileszs/ack.vim
if executable('rg')
  let g:ackprg = 'rg --vimgrep'
endif
" }}} -------------------------


" ----------- NERDTree settings {{{
" https://github.com/scrooloose/nerdtree
map <C-n> :NERDTreeToggle<CR>
" }}} -------------------------


" ----------- denite.vim settings {{{
" https://github.com/Shougo/denite.nvim
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
nnoremap <silent> ;/ :<C-u>Denite -buffer-name=search -auto-resize -auto-highlight line<CR>

" 横断検索
" 普通にgrep
nnoremap <silent> ;g :<C-u>Denite -buffer-name=search -mode=normal grep<CR>

" ctrlp
"nnoremap <silent> <C-p> :<C-u>Denite file_rec<CR>
nnoremap <silent> <C-p> :<C-u>Denite file_rec<CR>
nnoremap <silent> <C-l> :<C-u>DeniteProjectDir file_rec<CR>
" Option 1 : Set colors yourself
hi deniteMatchedChar ctermbg=NONE ctermfg=6
" Option 2 : link to other Highlight Group
hi link deniteMatchedChar Identifier

" resume previous buffer
"nnoremap <silent> ;r :<C-u>Denite -buffer-name=search -resume -mode=normal<CR>
nnoremap <silent> ;b :<C-u>Denite buffer -mode=normal<CR>
nnoremap <silent> ;r :<C-u>Denite register -mode=normal<CR>
" }}} -------------------------


" ----------- vim-gitgutter settings {{{
" https://github.com/airblade/vim-gitgutter
nnoremap <silent> ,gg :<C-u>GitGutterToggle<CR>
nnoremap <silent> ,gh :<C-u>GitGutterLineHighlightsToggle<CR>
" }}} -------------------------


" ----------- vim-markdown settings {{{
" https://github.com/plasticboy/vim-markdown
let g:vim_markdown_folding_disabled = 1
let g:vim_markdown_conceal = 0
let g:vim_markdown_conceal = 0
set conceallevel=0
" }}} -------------------------


" ----------- tender.vim settings {{{
" https://github.com/jacoborus/tender.vim
" If you have vim >=8.0 or Neovim >= 0.1.5
if (has("termguicolors"))
 set termguicolors
endif

" For Neovim 0.1.3 and 0.1.4
let $NVIM_TUI_ENABLE_TRUE_COLOR=1

" Theme
syntax enable
colorscheme tender
" }}} -------------------------


" ----------- etc settings {{{
" LXTerminal
" https://github.com/neovim/neovim/issues/6041
set guicursor=

" copy file relative path to register
" https://stackoverflow.com/questions/916875/yank-file-name-path-of-current-buffer-in-vim
:command! Cp let @+ = expand("%")

" copy gitlab.fdev url
" usage -> :Cpg
:function! s:GetGitlabURL()
:	let repo = system("git config -l | grep 'origin.url' | grep -oP '(?<=gitlab.fdev:)(.*)(?=.git)'")
:	let relativepath = "./" . expand("%")
:	let branch = "master"
:	let filepath = system('git ls-files --full-name ' . l:relativepath)
:	let @+ = "http://gitlab.fdev/" . l:repo . "/blob/" . l:branch . "/" . l:filepath
:	echo 'copied to your clipboard!'
:	return
:endfunction

":command! -nargs=1 Cpg call s:GetGitlabURL(<f-args>)
:command! Cpg call s:GetGitlabURL()

" reload init.vim
" :command! Rl source "~/.config/nvim/init.vim"
" }}} -------------------------

