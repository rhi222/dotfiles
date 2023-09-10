-- https://github.com/lukas-reineke/indent-blankline.nvim
-- vim.opt.list = true
-- vim.opt.listchars:append "tab:▸ "
-- ノイズ気味なので非表示にしたいかも
-- vim.opt.listchars:append "space:⋅"
-- vim.opt.listchars:append "eol:↴"

require("indent_blankline").setup({
	char = "|",
	-- 改行コードは好みじゃないので表示しない
	-- show_end_of_line = true,
	-- vscode同様、現在のネスト範囲をハイライト
	-- show_current_context = true,
	-- show_current_context_start = true,
})
