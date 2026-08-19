local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable", -- latest stable release
		lazypath,
	})
end

---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

local plugins = require("my/plugins")

-- https://github.com/folke/lazy.nvim#%EF%B8%8F-configuration
local opts = {
	defaults = {
		lazy = true,
	},
	-- rocks を要求するプラグインが無い（rest.nvim を最後に消えた）。
	-- 有効なままだと hererocks の実体が無い分だけ :checkhealth lazy が ❌ を出す
	rocks = { enabled = false },
}

require("lazy").setup(plugins, opts)
