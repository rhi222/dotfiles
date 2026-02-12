require("auto-session").setup({
	enabled = true,
	auto_save = true,
	auto_restore = true,
	suppressed_dirs = {
		vim.fn.expand("~"),
		vim.fn.expand("~/Downloads"),
	},
	-- Allow autosave when Neovim is launched with file arguments (e.g. `nvim .tmux.conf`)
	args_allow_files_auto_save = true,
})
