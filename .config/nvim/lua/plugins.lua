return {
	{
		"t9md/vim-quickhl",
		config = function()
			require("config/vim-quickhl")
		end,
	},
	-- filetype.luaと衝突するが、チーム開発する上でPJごとの設定を都度しなくて良いので、こちらを優先
	-- automatically adjusts 'shiftwidth' and 'expandtab' heuristically based on the current file
	{
		"tpope/vim-sleuth",
	},
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
		"phaazon/hop.nvim",
		config = function()
			require("config/hop")
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter",
		config = function()
			require("config/nvim-treesitter")
		end,
	},
	{
		"rebelot/kanagawa.nvim",
		config = function()
			require('config/kanagawa')
		end,
		lazy = true,
	},
	{
		"catppuccin/nvim",
		lazy = true,
	},
	{
		"folke/tokyonight.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			require("config/tokyonight")
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
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		config = function()
			require("config/indent-blankline")
		end,
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
	{
		"williamboman/mason.nvim",
		dependencies = {
			"williamboman/mason-lspconfig",
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
	-- LSP/補完
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
	{
		"nvim-telescope/telescope.nvim",
		tag = "0.1.2",
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
		"ibhagwan/fzf-lua",
		-- optional for icon support
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("config/fzf-lua")
			-- calling `setup` is optional for customization
		end,
	},
}
