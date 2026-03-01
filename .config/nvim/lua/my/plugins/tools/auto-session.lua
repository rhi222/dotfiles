require("auto-session").setup({
	enabled = true,
	auto_save = true,
	auto_restore = true,
	show_auto_restore_notif = true,
	suppressed_dirs = {
		vim.fn.expand("~"),
		vim.fn.expand("~/Downloads"),
		"/",
	},
	-- `nvim somefile` の終了時にプロジェクトセッションを上書きしないよう無効化。
	-- ファイル引数付き起動はセッション保存対象外とし、素のnvim起動のみ保存する。
	args_allow_files_auto_save = false,
	-- 削除済みworktree等の孤児セッションファイルを自動削除（30日）
	purge_after_minutes = 43200,
	-- tmux kill-server等でSIGHUP/SIGTERM受信中のセッション保存をスキップ
	pre_save_cmds = {
		function()
			if vim.v.dying > 0 then
				return false
			end
		end,
	},
})
