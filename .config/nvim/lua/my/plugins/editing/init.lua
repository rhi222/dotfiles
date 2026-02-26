local km = require("my.plugins.keymaps")
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
			km.lazy_key("editing", "hop_word", ":HopWord<CR>", { noremap = true }),
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
			km.lazy_key("editing", "flash_jump", function() require("flash").jump() end),
			km.lazy_key("editing", "flash_treesitter", function() require("flash").treesitter() end),
			km.lazy_key("editing", "flash_remote", function() require("flash").remote() end),
			km.lazy_key("editing", "flash_ts_search", function() require("flash").treesitter_search() end),
			km.lazy_key("editing", "flash_toggle", function() require("flash").toggle() end),
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
		event = { "BufReadPre", "BufNewFile" },
	},
	-- highlight
	{
		"t9md/vim-quickhl",
		keys = {
			km.lazy_key("editing", "quickhl_this", "<Plug>(quickhl-manual-this)", { noremap = true }),
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
