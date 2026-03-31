-- https://github.com/nvim-treesitter/nvim-treesitter
-- nvim 0.12+ では main ブランチを使用（master は非互換）
local parsers = {
	"bash",
	-- "csv",
	"css",
	"diff",
	"dockerfile",
	"fish",
	"gitcommit",
	"go",
	"graphql",
	"hcl",
	"html",
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
	"toml",
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

-- ハイライトとfoldingの有効化（filetypeベースで自動判定）
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("treesitter_setup", { clear = true }),
	callback = function()
		local lang = vim.treesitter.language.get_lang(vim.bo.filetype)
		if lang and pcall(vim.treesitter.language.add, lang) then
			pcall(vim.treesitter.start)
			vim.opt_local.foldmethod = "expr"
			vim.opt_local.foldexpr = "v:lua.vim.treesitter.foldexpr()"
		else
			vim.opt_local.foldmethod = "syntax"
		end
	end,
})
-- NOTE: CSV highlighting broken
-- https://github.com/nvim-treesitter/nvim-treesitter/issues/5330
-- highlightは https://github.com/cameron-wags/rainbow_csv.nvim で対応
