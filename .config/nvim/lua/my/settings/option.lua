-- options
vim.scriptencoding = "utf-8"

-- miseのnpm shimはshell scriptだが、Nvimはnodeで直接実行するため実体のJSを指定する
local node_host_bin = vim.fn.exepath("neovim-node-host")
vim.g.node_host_prog = vim.fn.glob(vim.fs.dirname(node_host_bin) .. "/../.mise/neovim@*/node_modules/neovim/bin/cli.js")
vim.g.python3_host_prog = vim.fn.exepath("python3")

-- checkhealthの警告抑制
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.opt.number = true
vim.opt.tabpagemax = 50
-- indent
-- filetype.luaで設定しているのでコメントアウト
-- vim.opt.tabstop = 4
-- vim.opt.softtabstop = 4
-- vim.opt.shiftwidth = 4
vim.opt.autoindent = true
vim.opt.smartindent = true
-- search
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
-- https://qiita.com/shiena/items/3f51a2c0b4722427e430
-- cursorlineとcursorcolumnのhighlightはcolerschemaとして採用しているvscode.luaで設定
vim.opt.cursorline = true
vim.opt.cursorcolumn = true
-- https://zenn.dev/shougo/articles/set-cmdheight-0
vim.opt.cmdheight = 0
-- clipboard
-- https://zenn.dev/koxya/articles/b71047cd88303b
-- https://zenn.dev/renoinn/scraps/f64fe35a81b753
vim.opt.clipboard = "unnamedplus"
if vim.fn.has("wsl") == 1 then
	vim.g.clipboard = {
		name = "win32yank-wsl",
		copy = {
			["+"] = "win32yank.exe -i --crlf",
			["*"] = "win32yank.exe -i --crlf",
		},
		-- 読み出しのフラグは --lf。`-o` に --crlf は無く、書くと exit 1 で落ちて
		-- unnamedplus 経由の貼り付けが丸ごと空になる（tests/nvim/test-clipboard.sh）
		paste = {
			["+"] = "win32yank.exe -o --lf",
			["*"] = "win32yank.exe -o --lf",
		},
		cache_enable = 0,
	}
end
-- TrueColor対応
vim.opt.termguicolors = true
-- ファイル末尾のEOLを自動追加しない
vim.opt.fixendofline = false
-- folding: nvim-treesitterに統合（デフォルトは無効）
vim.o.foldenable = false
-- セッションに載せる項目。消費者は2つある。
--   1. auto-session（buffers を含めて複数バッファを持たせる）
--   2. nvim 0.12.5 以降の :restart / ZR。`:h :restart` の
--      "To adjust what `:restart` restores, set 'sessionoptions'"
-- terminal を含めないので、どちらの復元でも terminal バッファは戻らない。
vim.opt.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,localoptions"
