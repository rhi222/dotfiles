return {
	{
		"lewis6991/gitsigns.nvim",
		config = function()
			require("my/plugins/git/gitsigns")
		end,
	},
	{
		"NeogitOrg/neogit",
		dependencies = {
			"nvim-lua/plenary.nvim", -- required
			"sindrets/diffview.nvim", -- optional - Diff integration
			"nvim-telescope/telescope.nvim", -- optional
		},
		keys = {
			{ "<leader>g", "<cmd>lua require('neogit').open()<CR>", mode = "n", desc = "neogit", noremap = true },
		},
		opts = {
			disable_line_numbers = false,
		},
	},
}
