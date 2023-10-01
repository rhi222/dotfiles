-- https://github.com/lukas-reineke/indent-blankline.nvim

require("ibl").setup({
	char = "|",
	-- 改行コードは好みじゃないので表示しない
	-- show_end_of_line = true,
	-- vscode同様、現在のネスト範囲をハイライト
	-- show_current_context = true,
	-- show_current_context_start = true,
})
