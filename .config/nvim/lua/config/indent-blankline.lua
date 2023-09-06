-- https://github.com/lukas-reineke/indent-blankline.nvim
vim.opt.list = true

require("indent_blankline").setup({
	char = "|",
	-- show_end_of_line = true,
	-- show_trailing_blankline_indent = false,
	-- space_char_blankline = " ",
})
