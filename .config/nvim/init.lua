-- require nvim v0.9.0 or later
-- -------------------- general mapping {{{
vim.scriptencoding = "utf-8"
vim.o.number = true
vim.o.tabpagemax = 50
-- indent
-- filetype.luaで設定しているのでコメントアウト
-- vim.o.tabstop = 4
-- vim.o.softtabstop = 4
-- vim.o.shiftwidth = 4
vim.o.autoindent = true
vim.o.smartindent = true
-- search
vim.o.incsearch = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.hlsearch = true
-- https://qiita.com/shiena/items/3f51a2c0b4722427e430
vim.o.cursorline = true
vim.o.cursorcolumn = true
-- https://zenn.dev/shougo/articles/set-cmdheight-0
vim.o.cmdheight = 0
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
-- https://github.com/volta-cli/volta/issues/866
vim.g.node_host_prog = vim.call("system", 'volta which neovim-node-host | tr -d "\n"')
vim.g.python_host_prog = vim.call("system", 'which python2 | tr -d "\n"')
vim.g.python3_host_prog = vim.call("system", 'which python3 | tr -d "\n"')
-- }}} -------------------------------

-- -------------------- key mapping {{{
vim.g.mapleader = " "
vim.g.maplocalleader = " "
-- }}} -------------------------------

-- -------------------- filetype {{{
-- https://zenn.dev/rapan931/articles/45b09b774512fc
local my_filetype = require("filetype")
vim.api.nvim_create_augroup("vimrc_augroup", {})
vim.api.nvim_create_autocmd("FileType", {
	group = "vimrc_augroup",
	pattern = "*",
	callback = function(args)
		my_filetype[args.match]()
	end,
})
-- }}} -------------------------------

-- -------------------- lazy.nvim {{{
-- https://github.com/folke/lazy.nvim
-- load lazy.nvim
-- see: https://github.com/euxn23/init-lua-and-lazy-nvim-sample
require("lazy_nvim")
-- }}} -------------------------------

-- -------------------- user command {{{
require("command")
-- }}} -------------------------------
