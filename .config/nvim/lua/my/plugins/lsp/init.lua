return {
	-- mason -> mason-lspconfig -> lspconfigの順番で設定が必要
	-- https://github.com/williamboman/mason-lspconfig.nvim#setup
	{
		"williamboman/mason.nvim",
		cmd = {
			"Mason",
			"MasonInstall",
			"MasonUninstall",
			"MasonUninstallAll",
			"MasonLog",
			"MasonUpdate",
		},
		opts = {},
	},
	{
		"williamboman/mason-lspconfig.nvim",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			"williamboman/mason.nvim",
			"neovim/nvim-lspconfig",
		},
		config = function()
			require("my/plugins/lsp/mason-lspconfig")
		end,
	},
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			{ "j-hui/fidget.nvim", tag = "v1.6.1", opts = {} },
			"hrsh7th/cmp-nvim-lsp",
		},
		config = function()
			require("my/plugins/lsp/nvim-lspconfig")
		end,
	},
	{
		"folke/lazydev.nvim",
		ft = "lua",
		opts = {
			library = {
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
			},
		},
	},
	{
		"RubixDev/mason-update-all",
		dependencies = { "williamboman/mason.nvim" },
		cmd = { "MasonUpdateAll" },
		config = function()
			require("mason").setup()
			require("mason-update-all").setup()
		end,
	},
	-- formatter: star数の多いconform.nvimに移行
	{
		"stevearc/conform.nvim",
		config = function()
			require("my/plugins/lsp/conform")
		end,
		event = { "BufWritePre" },
		cmd = {
			"ConformInfo",
			"Format",
			"FormatDisable",
			"FormatEnable",
		},
	},
}
