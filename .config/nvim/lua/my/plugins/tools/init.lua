local km = require("my.plugins.keymaps")
return {
	{
		"rmagatti/auto-session",
		lazy = false,
		config = function()
			require("my/plugins/tools/auto-session")
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
			require("my/plugins/tools/rest-nvim")
		end,
		keys = {
			km.lazy_key("tools", "rest_run", "<cmd>Rest run<CR>"),
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
			vim.g.mkdp_theme = "light"
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
			km.lazy_key("tools", "sidekick_jump", function()
				-- if there is a next edit, jump to it, otherwise apply it if any
				if not require("sidekick").nes_jump_or_apply() then
					return "<Tab>" -- fallback to normal tab
				end
			end, { expr = true }),
			km.lazy_key("tools", "sidekick_toggle", function()
				require("sidekick.cli").toggle()
			end),
			km.lazy_key("tools", "sidekick_toggle2", function()
				require("sidekick.cli").toggle()
			end),
			km.lazy_key("tools", "sidekick_select", function()
				require("sidekick.cli").select()
			end),
			km.lazy_key("tools", "sidekick_close", function()
				require("sidekick.cli").close()
			end),
			km.lazy_key("tools", "sidekick_send", function()
				require("sidekick.cli").send({ msg = "{this}" })
			end),
			km.lazy_key("tools", "sidekick_file", function()
				require("sidekick.cli").send({ msg = "{file}" })
			end),
			km.lazy_key("tools", "sidekick_visual", function()
				require("sidekick.cli").send({ msg = "{selection}" })
			end),
			km.lazy_key("tools", "sidekick_prompt", function()
				require("sidekick.cli").prompt()
			end),
			km.lazy_key("tools", "sidekick_claude", function()
				require("sidekick.cli").toggle({ name = "claude", focus = true })
			end),
		},
	},
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		opts = {}, -- this is equalent to setup({}) function
	},
}
