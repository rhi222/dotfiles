-- https://github.com/nvim-treesitter/nvim-treesitter
require("nvim-treesitter.configs").setup({
	ensure_installed = {
		"bash",
		-- "csv",
		"fish",
		"graphql",
		"hcl",
		"http",
		"javascript",
		"json",
		"json5",
		"lua",
		"markdown",
		"mermaid",
		"prisma",
		"python",
		"sql",
		-- "tsv",
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
-- NOTE: CSV highlighting broken
-- https://github.com/nvim-treesitter/nvim-treesitter/issues/5330
-- highlightは https://github.com/cameron-wags/rainbow_csv.nvim で対応
