-- options
vim.scriptencoding = "utf-8"

-- path: 起動時のパフォーマンス最適化のため遅延実行
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		vim.schedule(function()
			-- checkhelathするとErrorになるが、:echo g:node_host_progすると設定できている
			-- checkhealthはVimEnterより前に実行されるため
			vim.g.node_host_prog = vim.fn.trim(vim.fn.system("which node"))
			vim.g.python_host_prog = vim.fn.trim(vim.fn.system("which python2"))
			vim.g.python3_host_prog = vim.fn.trim(vim.fn.system("which python3"))
		end)
	end,
})

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
if vim.fn.has("wsl") then
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
-- auto-session: ensure multiple buffers are persisted
vim.opt.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"

-- wslで貼り付けにC-vを割り当てたためremap
-- Ctrl+Shift+VでVisual Blockモードに入る
vim.keymap.set({ "n", "v" }, "<C-S-v>", "<C-v>", { silent = true })
