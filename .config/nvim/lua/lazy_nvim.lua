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
	-- rest.nvim の rockspec は luarocks に無い tree-sitter-http 0.0.35 を要求して build が落ちる。
	-- 依存は plugin spec 側で宣言し、luarocks は使わない
	rocks = { enabled = false },
}

require("lazy").setup(plugins, opts)
