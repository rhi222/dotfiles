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
		config = function()
			require("my/plugins/ui/vscode")
		end,
	},
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
	},
}
