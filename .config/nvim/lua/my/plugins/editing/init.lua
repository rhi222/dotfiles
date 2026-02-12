return {
	{
		"nvim-treesitter/nvim-treesitter",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			require("my/plugins/editing/nvim-treesitter")
		end,
		dependencies = {
			"nvim-treesitter/playground",
		},
	},
	-- easymotion
	{
		-- NOTE: 本家はneovim 0.11対応しないためforkを採用
		-- "phaazon/hop.nvim",
		"smoka7/hop.nvim",
		version = "*",
		keys = {
			{ "<leader>j", ":HopWord<CR>", mode = "n", desc = "hop word", noremap = true },
		},
		opts = {
			keys = "asdghklqwertyuiopzxcvbnmfj",
			create_hl_autocmd = true,
		},
	},
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		opts = {},
		-- stylua: ignore
		keys = {
			{ "gs", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
			{ "gS", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
			{ "gr", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
			{ "gR", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
			{ "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
		},
	},
	{
		"numToStr/Comment.nvim",
		event = "BufRead",
		config = function()
			require("my/plugins/editing/comment")
		end,
	},
	{
		"folke/todo-comments.nvim",
		event = "BufRead",
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {},
	},
	-- filetype.luaと衝突するが、チーム開発する上でPJごとの設定を都度しなくて良いので、こちらを優先
	-- automatically adjusts 'shiftwidth' and 'expandtab' heuristically based on the current file
	{
		"tpope/vim-sleuth",
	},
	-- highlight
	{
		"t9md/vim-quickhl",
		keys = {
			{
				"<leader>m",
				"<Plug>(quickhl-manual-this)",
				mode = "n",
				desc = "quickhl manual this",
				noremap = true,
			},
		},
		cmd = {
			"QuickhlManualAdd",
		},
	},
	{
		"kevinhwang91/nvim-hlslens",
		event = "VeryLazy",
		opts = {},
	},
}
