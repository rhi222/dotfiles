-- https://github.com/nvim-treesitter/nvim-treesitter
-- nvim 0.12+ では main ブランチを使用（master は非互換）
local parsers = {
	"bash",
	-- "csv",
	"diff",
	"fish",
	"graphql",
	"hcl",
	"http",
	"javascript",
	"json",
	"json5",
	"lua",
	"markdown",
	"markdown_inline",
	"mermaid",
	"prisma",
	"python",
	"regex",
	"sql",
	-- "tsv",
	"tsx",
	"typescript",
	"vim",
	"vimdoc",
	"xml",
	"yaml",
}

-- パーサーのインストール
require("nvim-treesitter").install(parsers)

-- ハイライトの有効化
vim.api.nvim_create_autocmd("FileType", {
	pattern = parsers,
	callback = function()
		pcall(vim.treesitter.start)
	end,
})
-- NOTE: CSV highlighting broken
-- https://github.com/nvim-treesitter/nvim-treesitter/issues/5330
-- highlightは https://github.com/cameron-wags/rainbow_csv.nvim で対応
