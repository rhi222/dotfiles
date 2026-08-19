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
	-- nvim-treesitter への依存は持たない。kulala は自前の kulala_http パーサを
	-- tree-sitter CLI で生成し、ft http を language.register で奪うため。
	{
		"mistweaverco/kulala.nvim",
		ft = "http",
		config = function()
			require("my/plugins/tools/kulala")
		end,
		keys = {
			-- ft を付けてバッファローカルにする。rest.nvim 時代はグローバル束縛だったため
			-- 全バッファで <C-e>（既定のスクロール）が潰れていた
			km.lazy_key("tools", "kulala_run", function()
				require("kulala").run()
			end, { ft = "http" }),
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
