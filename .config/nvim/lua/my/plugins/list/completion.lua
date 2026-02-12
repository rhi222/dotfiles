return {
	-- copilot: 処理が早く、最近のプラグインとの統合が容易(と言っている)ため、.vimでなく.luaを採用
	{
		"zbirenbaum/copilot.lua",
		event = "InsertEnter",
		config = function()
			require("my/plugins/copilot")
		end,
	},
	{
		"CopilotC-Nvim/CopilotChat.nvim",
		event = "VeryLazy",
		-- note: 未指定の場合、deprecatedなcanaryブランチを参照していた。明示的にmainブランチを指定
		branch = "main",
		dependencies = {
			{ "zbirenbaum/copilot.lua" }, -- or github/copilot.vim
			{ "nvim-lua/plenary.nvim" }, -- for curl, log wrapper
			{ "nvim-telescope/telescope.nvim" },
		},
		build = "make tiktoken",
		config = function()
			require("my/plugins/copilot-chat")
		end,
		keys = {
			{
				"<leader>cp",
				function()
					require("CopilotChat").select_prompt({ context = { "buffers" } })
				end,
				desc = "CopilotChat - Prompts",
			},
			{
				"<leader>cp",
				function()
					require("CopilotChat").select_prompt()
				end,
				mode = "x",
				desc = "CopilotChat - Prompts",
			},
			{
				"<leader>cd",
				":CopilotChatShowPrompt<CR>",
				mode = { "x", "n", "i" },
				desc = "CopilotChat - show Prompts",
			},
		},
	},
	{
		"zbirenbaum/copilot-cmp",
		opts = {},
	},
	{
		"hrsh7th/nvim-cmp",
		event = { "InsertEnter", "CmdlineEnter" },
		dependencies = {
			-- TODO: 要精査
			"hrsh7th/cmp-nvim-lsp", --LSPを補完ソースに
			"hrsh7th/cmp-buffer", --bufferを補完ソースに
			"hrsh7th/cmp-cmdline", -- vimのコマンド
			"hrsh7th/cmp-path", --pathを補完ソースに
			"hrsh7th/vim-vsnip", --スニペットエンジン
			-- 'hrsh7th/cmp-vsnip', --スニペットを補完ソースに
			"onsails/lspkind.nvim", --補完欄にアイコンを表示
			"zbirenbaum/copilot-cmp", --copilotを補完ソースに
		},
		config = function()
			require("my/plugins/nvim-cmp")
		end,
	},
}
