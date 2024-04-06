-- https://github.com/nvim-lualine/lualine.nvim
require("lualine").setup({
	sections = {
		-- show fullpath
		lualine_c = { { "filename", path = 2 } },
		-- fileformatは非表示
		lualine_x = {'filetype', 'encoding'},
	},
})
