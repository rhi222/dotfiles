return {
	{
		't9md/vim-quickhl',
		config = function()
			require('config/vim-quickhl')
		end
	},
	{
		'nvim-lualine/lualine.nvim',
		config = function()
			require('config/lualine')
		end
	},
	{
		'nvim-telescope/telescope.nvim',
		tag = '0.1.2',
		dependencies = { 'nvim-lua/plenary.nvim' },
		config = function()
			require('config/telescope')
		end
	},
	{
		'nvim-telescope/telescope-file-browser.nvim',
		dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
	},
	{
		'lewis6991/gitsigns.nvim',
		config = function()
			require('config/gitsigns')
		end
	},
	{
		'phaazon/hop.nvim',
		config = function()
			require('config/hop')
		end
	},
	{
		'nvim-treesitter/nvim-treesitter',
		config = function()
			require('config/nvim-treesitter')
		end
	},
	-- colorschemaは検討中
	{
		'rebelot/kanagawa.nvim',
		config = function()
			require('config/kanagawa')
		end
	},
	-- {
	-- 	'folke/tokyonight.nvim',
	-- },
	-- {
	-- 	'catppuccin/nvim',
	-- },
	{
		'zbirenbaum/copilot.lua',
		config = function()
			require('config/copilot')
		end
	},
	{
		'lukas-reineke/indent-blankline.nvim',
		config = function()
			require('config/indent-blankline')
		end
	},
	-- LSP/補完
	{ 'neovim/nvim-lspconfig' },
	{ 'williamboman/mason.nvim' },
	{ 'williamboman/mason-lspconfig' },
	{
		'hrsh7th/nvim-cmp',
		dependencies = {
			'hrsh7th/cmp-nvim-lsp', --LSPを補完ソースに
			'hrsh7th/cmp-buffer', --bufferを補完ソースに
			-- 'hrsh7th/cmp-path', --pathを補完ソースに
			'hrsh7th/vim-vsnip', --スニペットエンジン
			-- 'hrsh7th/cmp-vsnip', --スニペットを補完ソースに
			'onsails/lspkind.nvim' --補完欄にアイコンを表示
		},
		config = function()
			require('config/nvim-cmp')
		end
	}
	-- {}
}
