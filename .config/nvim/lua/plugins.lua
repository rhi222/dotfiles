return {
	{
		"nvim-lualine/lualine.nvim",
		config = function()
			require("config/lualine")
		end,
	},
	{
		"lewis6991/gitsigns.nvim",
		config = function()
			require("config/gitsigns")
		end,
	},
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		config = function()
			require("config/indent-blankline")
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter",
		config = function()
			require("config/nvim-treesitter")
		end,
		dependencies = {
			"nvim-treesitter/playground",
		},
		tag = "v0.9.2",
	},
	{
		"rebelot/kanagawa.nvim",
		lazy = true,
		config = function()
			require("config/kanagawa")
		end,
	},
	{
		"catppuccin/nvim",
		lazy = true,
	},
	{
		"folke/tokyonight.nvim",
		lazy = true,
		config = function()
			require("config/tokyonight")
		end,
	},
	-- nvim-treesitterのsyntax highlightが絶妙に見にくかったのでtokyonightから乗り換え
	-- https://github.com/rockerBOO/awesome-neovim?tab=readme-ov-file#tree-sitter-supported-colorscheme からpickした
	{
		"Mofiqul/vscode.nvim",
		config = function()
			require("config/vscode")
		end,
	},
	-- copilot.lua使ってみたいが、keymapがうまく出来ずに保留
	-- {
	-- 	'zbirenbaum/copilot.lua',
	-- 	config = function()
	-- 		require('config/copilot')
	-- 	end
	-- },
	{
		"github/copilot.vim",
		event = "InsertEnter",
	},
	{
		"hrsh7th/nvim-cmp",
		event = "InsertEnter",
		dependencies = {
			-- TODO: 要精査
			"hrsh7th/cmp-nvim-lsp", --LSPを補完ソースに
			"hrsh7th/cmp-buffer", --bufferを補完ソースに
			"hrsh7th/cmp-cmdline", -- vimのコマンド
			"hrsh7th/cmp-path", --pathを補完ソースに
			"hrsh7th/vim-vsnip", --スニペットエンジン
			-- 'hrsh7th/cmp-vsnip', --スニペットを補完ソースに
			"onsails/lspkind.nvim", --補完欄にアイコンを表示
		},
		config = function()
			require("config/nvim-cmp")
		end,
	},
	-- LSP
	{
		"williamboman/mason.nvim",
		dependencies = {
			"williamboman/mason-lspconfig",
			{
				"neovim/nvim-lspconfig",
				dependencies = {
					-- Useful status updates for LSP
					-- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
					{ "j-hui/fidget.nvim", tag = "legacy", opts = {} },
					-- Additional lua configuration, makes nvim stuff amazing!
					{ "folke/neodev.nvim", opts = {} },
				},
				config = function()
					require("config/nvim-lspconfig")
				end,
			},
		},
		-- lspの設定もここで実施しているのでlazyloadしない
		-- cmd = {
		-- 	"Mason",
		-- 	"MasonInstall",
		-- 	"MasonUninstall",
		-- 	"MasonUninstallAll",
		-- 	"MasonLog",
		-- 	"MasonUpdate",
		-- },
		config = function()
			require("config/mason")
		end,
	},
	{
		"mhartington/formatter.nvim",
		cmd = {
			"Format",
			"FormatWrite",
			"FormatLock",
			"FormatWriteLock",
		},
		config = function()
			require("config/formatter")
		end,
	},
	-- finder
	{
		"nvim-telescope/telescope.nvim",
		tag = "0.1.6", -- 公式READMEがtag指定推奨
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				-- NOTE:
				-- If you are having trouble with this installation,
				-- refer to the README for telescope-fzf-native for more instructions.
				build = "make",
				cond = function()
					return vim.fn.executable("make") == 1
				end,
			},
			{
				"nvim-telescope/telescope-file-browser.nvim",
			},
		},
		config = function()
			require("config/telescope")
		end,
	},
	{
		"ibhagwan/fzf-lua",
		-- optional for icon support
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("config/fzf-lua")
			-- calling `setup` is optional for customization
		end,
	},
	-- other
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		opts = {}, -- this is equalent to setup({}) function
	},
	{
		"nvim-tree/nvim-web-devicons",
	},
	{
		"kevinhwang91/nvim-hlslens",
	},
	{
		"t9md/vim-quickhl",
		config = function()
			require("config/vim-quickhl")
		end,
	},
	{
		"phaazon/hop.nvim",
		config = function()
			require("config/hop")
		end,
	},
	-- filetype.luaと衝突するが、チーム開発する上でPJごとの設定を都度しなくて良いので、こちらを優先
	-- automatically adjusts 'shiftwidth' and 'expandtab' heuristically based on the current file
	{
		"tpope/vim-sleuth",
	},
	{
		"folke/which-key.nvim",
		cmd = {
			"WhichKey",
		},
		init = function()
			vim.o.timeout = true
			vim.o.timeoutlen = 300
		end,
	},
	{
		"rest-nvim/rest.nvim",
		dependencies = { { "nvim-lua/plenary.nvim" } },
		ft = "http",
		tag = "v1.2.1", -- 2024/03/23 の最新はv2.0.1だがエラーが出るため、様子見
		config = function()
			require("config/rest-nvim")
		end,
	},
	-- markdown preview
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		ft = { "markdown" },
		build = function()
			vim.fn["mkdp#util#install"]()
		end,
	},
	-- -- 開発が活発な↓を使いたいが、plantuml非対応の為arkdown-preview.nvimを利用
	-- {
	-- 	"toppair/peek.nvim",
	-- 	event = { "VeryLazy" },
	-- 	build = "deno task --quiet build:fast",
	-- 	config = function()
	-- 		require("peek").setup()
	-- 		vim.api.nvim_create_user_command("PeekOpen", require("peek").open, {})
	-- 		vim.api.nvim_create_user_command("PeekClose", require("peek").close, {})
	-- 	end,
	-- },
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
}
