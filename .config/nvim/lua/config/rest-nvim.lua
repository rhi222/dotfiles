require("rest-nvim").setup({
	-- Open request results in a horizontal split
	result_split_horizontal = false,
	-- Keep the http file buffer above|left when split horizontal|vertical
	result_split_in_place = false,
	-- Skip SSL verification, useful for unknown certificates
	skip_ssl_verification = false,
	-- Highlight request on run
	highlight = {
		enabled = true,
		timeout = 150,
	},
	-- Jump to request line on run
	jump_to_request = false,
	env_file = ".env",
	yank_dry_run = true,
})
vim.api.nvim_set_keymap("n", "<C-e>", "<Plug>RestNvim", { noremap = true })
vim.api.nvim_set_keymap("n", "<C-c>", "<Plug>RestNvimPreview", { noremap = true })
