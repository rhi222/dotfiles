-- https://github.com/nvim-lualine/lualine.nvim
require("lualine").setup({
	options = {
		-- NOTE: trueだとalacrittyで表示崩れする
		-- lualine_bにdiagnostics設定時 -> error, warnなど複数種類あるとき
		-- lualine_xにfiletype設定時 -> txtファイル開いたとき
		icons_enabled = false,
	},
	sections = {
		lualine_b = { "branch", "diff" },
		-- show fullpath
		lualine_c = { { "filename", path = 2 } },
		lualine_x = { "filetype", "encoding" },
	},
})
