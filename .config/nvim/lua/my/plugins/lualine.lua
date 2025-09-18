-- https://github.com/nvim-lualine/lualine.nvim
require("lualine").setup({
	options = {
		-- NOTE: trueだとalacrittyで表示崩れする
		-- lualine_bにdiagnostics設定時 -> error, warnなど複数種類あるとき
		-- lualine_xにfiletype設定時 -> txtファイル開いたとき
		icons_enabled = false,
	},
	sections = {
		-- branchは非表示, filenameの表示スペースを確保したい
		lualine_b = { "diff" },
		-- pathの値で表示形式を変更可能
		-- 0: Just the filename
		-- 1: Relative path
		-- 2: Absolute path
		-- 3: Absolute path, with tilde as the home directory
		-- 4: Filename and parent dir, with tilde as the home directory
		lualine_c = { { "filename", path = 1 } },
		lualine_x = { "filetype", "encoding" },
	},
})
