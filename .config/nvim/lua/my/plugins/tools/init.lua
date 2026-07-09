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
		build = ":call mkdp#util#install()",
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
	-- sidekick.nvim は削除: CLI連携(claude/codex)はtmuxペイン直接運用のため不採用と確定
	-- plantuml syntax + preview
	{
		"weirongxu/plantuml-previewer.vim",
		ft = "plantuml",
		dependencies = { "aklt/plantuml-syntax" },
		config = function()
			-- プラグインがPlantumlOpenコマンドを上書きするため、ロード後に再定義
			require("my/commands/plantuml").create_commands()
		end,
	},
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		opts = {}, -- this is equalent to setup({}) function
	},
}
