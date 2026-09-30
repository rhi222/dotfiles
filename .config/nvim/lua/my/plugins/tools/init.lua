local km = require("my.plugins.keymaps")

local function add_to_package_path(plugin)
	package.path = plugin.dir .. "/?.lua;" .. plugin.dir .. "/?/init.lua;" .. package.path
end

return {
	{
		"rmagatti/auto-session",
		lazy = false,
		config = function()
			require("my/plugins/tools/auto-session")
		end,
	},
	-- http client
	-- rockspec の依存を luarocks を使わずに入れる（lazy_nvim.lua の rocks 参照）。
	-- http parser は nvim-treesitter が入れる。
	{
		"rest-nvim/rest.nvim",
		ft = "http",
		dependencies = {
			"nvim-neotest/nvim-nio",
			"j-hui/fidget.nvim",
			-- 純 Lua の rock。module が repo 直下にあり rtp の lua/ から引けないため package.path に足す
			{ "manoelcampos/xml2lua", config = add_to_package_path },
			{ "lunarmodules/lua-mimetypes", config = add_to_package_path },
		},
		config = function()
			require("my/plugins/tools/rest-nvim")
		end,
		keys = {
			-- ft を付けてバッファローカルにする。グローバル束縛だと
			-- 全バッファで <C-e>（既定のスクロール）が潰れる
			km.lazy_key("tools", "rest_run", "<cmd>Rest run<CR>", { ft = "http" }),
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
