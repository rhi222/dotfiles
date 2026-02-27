local km = require("my.plugins.keymaps")
return {
	-- copilot: 処理が早く、最近のプラグインとの統合が容易(と言っている)ため、.vimでなく.luaを採用
	{
		"zbirenbaum/copilot.lua",
		event = "InsertEnter",
		config = function()
			require("my/plugins/completion/copilot")
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
			require("my/plugins/completion/copilot-chat")
		end,
		keys = {
			km.lazy_key("completion", "chat_prompts_n", function()
				require("CopilotChat").select_prompt({ context = { "buffers" } })
			end),
			km.lazy_key("completion", "chat_prompts_x", function()
				require("CopilotChat").select_prompt()
			end),
			km.lazy_key("completion", "chat_show_prompt", ":CopilotChatShowPrompt<CR>"),
		},
	},
	{
		"hrsh7th/nvim-cmp",
		event = { "InsertEnter", "CmdlineEnter" },
		dependencies = {
			"hrsh7th/cmp-nvim-lsp", --LSPを補完ソースに
			"hrsh7th/cmp-buffer", --bufferを補完ソースに
			"hrsh7th/cmp-cmdline", -- vimのコマンド
			"hrsh7th/cmp-path", --pathを補完ソースに
			"onsails/lspkind.nvim", --補完欄にアイコンを表示
			"folke/lazydev.nvim", -- Neovim Lua API補完
		},
		config = function()
			require("my/plugins/completion/nvim-cmp")
		end,
	},
}
