-- options
vim.scriptencoding = "utf-8"

-- providers: 外部プロセスを起動せずパスを解決
vim.g.node_host_prog = vim.fn.exepath("neovim-node-host")
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
		paste = {
			["+"] = "win32yank.exe -o --crlf",
			["*"] = "win32yank.exe -o --crlf",
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
-- auto-session: ensure multiple buffers are persisted
vim.opt.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,localoptions"

-- html filetype に formatprg を設定（rest-nvim の checkhealth 警告回避）
vim.api.nvim_create_autocmd("FileType", {
	pattern = "html",
	callback = function()
		vim.bo.formatprg = "prettier --parser html"
	end,
})

