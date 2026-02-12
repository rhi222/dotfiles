-- https://github.com/lewis6991/gitsigns.nvim
local km = require("my.plugins.keymaps")
require("gitsigns").setup({
	on_attach = function(bufnr)
		local gs = package.loaded.gitsigns
		local lhs, mode, desc = km.get("git", "toggle_blame")
		vim.keymap.set(mode, lhs, gs.toggle_current_line_blame, { buffer = bufnr, desc = desc })
	end,
})
