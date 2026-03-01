return {
	-- TODO: lualineがalacrittyで表示崩れ。代替を探す
	-- https://github.com/yutkat/my-neovim-pluginlist/blob/main/statusline.md
	{
		"nvim-lualine/lualine.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			require("my/plugins/ui/lualine")
		end,
	},
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		event = "VeryLazy",
		config = function()
			require("my/plugins/ui/indent-blankline")
		end,
	},
	{
		"shellRaining/hlchunk.nvim",
		enabled = false,
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			require("my/plugins/ui/hlchunk")
		end,
	},
	{
		"nvim-tree/nvim-web-devicons",
	},
	-- colorscheme
	{
		"catppuccin/nvim",
		lazy = true,
	},
	{
		"folke/tokyonight.nvim",
		lazy = true,
		config = function()
			require("my/plugins/ui/tokyonight")
		end,
	},
	-- nvim-treesitterのsyntax highlightが絶妙に見にくかったのでtokyonightから乗り換え
	-- https://github.com/rockerBOO/awesome-neovim?tab=readme-ov-file#tree-sitter-supported-colorscheme からpickした
	{
		"Mofiqul/vscode.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			require("my/plugins/ui/vscode")
		end,
	},
	{
		"folke/snacks.nvim",
		lazy = false,
		priority = 1000,
		opts = {
			image = { enabled = false },
			notifier = { enabled = false },
		},
		config = function(_, opts)
			require("snacks").setup(opts)
			-- WSL2+tmux環境ではkitty graphics protocol非対応のためcheckhealthも抑制
			require("snacks.image").meta.health = false
		end,
	},
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
		opts = {
			icons = {
				mappings = false,
			},
		},
	},
	{
		"folke/noice.nvim",
		event = "VeryLazy",
		dependencies = {
			"MunifTanjim/nui.nvim",
		},
		config = function()
			require("my/plugins/ui/noice")
		end,
	},
}
