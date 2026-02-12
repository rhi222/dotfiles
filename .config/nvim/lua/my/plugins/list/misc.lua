return {
	{
		"rmagatti/auto-session",
		lazy = false,
		config = function()
			require("my/plugins/auto-session")
		end,
	},
	-- http client
	{
		"rest-nvim/rest.nvim",
		ft = "http",
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			opts = function(_, opts)
				opts.ensure_installed = opts.ensure_installed or {}
				table.insert(opts.ensure_installed, "http")
			end,
		},
		config = function()
			require("my/plugins/rest-nvim")
		end,
		keys = {
			{ "<C-e>", "<cmd>Rest run<CR>", mode = "n", desc = "Run rest command" },
		},
	},
	-- markdown preview
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		ft = { "markdown" },
		build = "cd app && yarn install",
		init = function()
			vim.g.mkdp_filetypes = { "markdown" }
		end,
		config = function()
			require("my/plugins/markdown-preview")
		end,
	},
	-- https://github.com/cameron-wags/rainbow_csv.nvim
	{
		"cameron-wags/rainbow_csv.nvim",
		config = true,
		ft = {
			"csv",
			"tsv",
			"csv_semicolon",
			"csv_whitespace",
			"csv_pipe",
			"rfc_csv",
			"rfc_semicolon",
		},
		cmd = {
			"RainbowDelim",
			"RainbowDelimSimple",
			"RainbowDelimQuoted",
			"RainbowMultiDelim",
		},
	},
	-- https://github.com/folke/sidekick.nvim?tab=readme-ov-file
	{
		"folke/sidekick.nvim",
		opts = {
			-- add any options here
			cli = {
				mux = {
					backend = "tmux",
					enabled = true,
				},
			},
		},
		keys = {
			{
				"<tab>",
				function()
					-- if there is a next edit, jump to it, otherwise apply it if any
					if not require("sidekick").nes_jump_or_apply() then
						return "<Tab>" -- fallback to normal tab
					end
				end,

				expr = true,
				desc = "Goto/Apply Next Edit Suggestion",
			},
			{
				"<c-.>",
				function()
					require("sidekick.cli").toggle()
				end,
				desc = "Sidekick Toggle",
				mode = { "n", "t", "i", "x" },
			},

			{
				"<leader>st",
				function()
					require("sidekick.cli").toggle()
				end,
				desc = "Sidekick Toggle CLI",
			},
			{
				"<leader>ss",
				function()
					require("sidekick.cli").select()
				end,
				desc = "Select CLI",
			},
			{
				"<leader>sd",
				function()
					require("sidekick.cli").close()
				end,
				desc = "Detach a CLI Session",
			},
			{
				"<leader>se",
				function()
					require("sidekick.cli").send({ msg = "{this}" })
				end,
				mode = { "x", "n" },
				desc = "Send This",
			},
			{
				"<leader>sf",
				function()
					require("sidekick.cli").send({ msg = "{file}" })
				end,
				desc = "Send File",
			},
			{
				"<leader>sv",
				function()
					require("sidekick.cli").send({ msg = "{selection}" })
				end,
				mode = { "x" },
				desc = "Send Visual Selection",
			},
			{
				"<leader>sp",
				function()
					require("sidekick.cli").prompt()
				end,
				mode = { "n", "x" },
				desc = "Sidekick Select Prompt",
			},
			{
				"<leader>sc",
				function()
					require("sidekick.cli").toggle({ name = "claude", focus = true })
				end,
				desc = "Sidekick Toggle Claude",
			},
		},
	},
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		opts = {}, -- this is equalent to setup({}) function
	},
}
