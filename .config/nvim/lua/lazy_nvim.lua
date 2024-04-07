local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
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

local plugins = require("my/plugin")

-- https://github.com/folke/lazy.nvim#%EF%B8%8F-configuration
local opts = {
	-- defaults = {
	-- 	lazy = true,
	-- },
}

require("lazy").setup(plugins, opts)
