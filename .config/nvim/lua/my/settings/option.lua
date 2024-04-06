-- options
vim.scriptencoding = "utf-8"

-- path
-- https://github.com/volta-cli/volta/issues/866
vim.g.node_host_prog = vim.call("system", 'volta which neovim-node-host | tr -d "\n"')
vim.g.python_host_prog = vim.call("system", 'which python2 | tr -d "\n"')
vim.g.python3_host_prog = vim.call("system", 'which python3 | tr -d "\n"')

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
