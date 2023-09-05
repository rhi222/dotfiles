-- https://github.com/nvim-treesitter/nvim-treesitter
require("nvim-treesitter.configs").setup({
	ensure_installed = {
		"bash",
		"fish",
		"graphql",
		"javascript",
		"lua",
		"markdown",
		"python",
		"sql",
		"tsv",
		"tsx",
		"typescript",
		"vim",
		"vimdoc",
		"xml",
		"yaml",
	},
	highlight = {
		enable = true,
	},
})
