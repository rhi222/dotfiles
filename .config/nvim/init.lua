-- require nvim v0.9.0 or later
require('my/settings/option')

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
require("my/command")
-- }}} -------------------------------
