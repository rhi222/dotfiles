-- https://github.com/folke/tokyonight.nvim
require("tokyonight").setup({
	style = "moon",
	on_colors = function(_) end,
	on_highlights = function(_, _) end,
})

vim.cmd([[colorscheme tokyonight]])
