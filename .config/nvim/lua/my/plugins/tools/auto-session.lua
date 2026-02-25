require("auto-session").setup({
	enabled = true,
	auto_save = true,
	auto_restore = true,
	suppressed_dirs = {
		vim.fn.expand("~"),
		vim.fn.expand("~/Downloads"),
	},
	-- `nvim somefile` の終了時にプロジェクトセッションを上書きしないよう無効化。
	-- ファイル引数付き起動はセッション保存対象外とし、素のnvim起動のみ保存する。
	args_allow_files_auto_save = false,
})
