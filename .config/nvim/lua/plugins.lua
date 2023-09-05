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
		-- config = function()
		-- 	require('config/kanagawa')
		-- end
	},
	-- 'rktjmp/lush.nvim',
	{
		'folke/tokyonight.nvim',
		lazy = false,
		priority = 1000,
		config = function()
			require('config/tokyonight')
		end
	},
	{
		'catppuccin/nvim',
	},
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
	{
		'neovim/nvim-lspconfig',
		dependencies = {
			-- Useful status updates for LSP
			-- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
			{ 'j-hui/fidget.nvim', tag = 'legacy', opts = {} },
			 -- Additional lua configuration, makes nvim stuff amazing!
			'folke/neodev.nvim',
    	},
	},
	{
		'williamboman/mason.nvim',
		dependencies = {
			'williamboman/mason-lspconfig'
		},
		-- 遅延ロードを試してみる
		-- https://zenn.dev/yuucu/articles/lazy_nvim_tuning#%E9%81%85%E5%BB%B6%E3%83%AD%E3%83%BC%E3%83%89%E8%A8%AD%E5%AE%9A%E3%81%AE%E7%B4%B9%E4%BB%8B%E3%81%A8%E5%AE%9F%E4%BE%8B
		cmd = {
		  "Mason",
		  "MasonInstall",
		  "MasonUninstall",
		  "MasonUninstallAll",
		  "MasonLog",
		  "MasonUpdate",
		},
		-- config = function()
		-- 	require('config/mason')
		-- end
	},
	{
		'hrsh7th/nvim-cmp',
		dependencies = {
			-- TODO: 要精査
			'hrsh7th/cmp-nvim-lsp', --LSPを補完ソースに
			'hrsh7th/cmp-buffer', --bufferを補完ソースに
			'hrsh7th/cmp-cmdline', -- vimのコマンド
			'hrsh7th/cmp-path', --pathを補完ソースに
			'hrsh7th/vim-vsnip', --スニペットエンジン
			-- 'hrsh7th/cmp-vsnip', --スニペットを補完ソースに
			'onsails/lspkind.nvim' --補完欄にアイコンを表示
		},
		config = function()
			require('config/nvim-cmp')
		end
	},
	{
		'mhartington/formatter.nvim',
		config = function()
			require('config/formatter')
		end
	},
	{
		'nvim-telescope/telescope.nvim',
		tag = '0.1.2',
		dependencies = {
			'nvim-lua/plenary.nvim',
			-- Fuzzy Finder Algorithm which requires local dependencies to be built.
			-- Only load if `make` is available. Make sure you have the system
			-- requirements installed.
			{
			  'nvim-telescope/telescope-fzf-native.nvim',
			  -- NOTE: If you are having trouble with this installation,
			  --       refer to the README for telescope-fzf-native for more instructions.
			  build = 'make',
			  cond = function()
			    return vim.fn.executable 'make' == 1
			  end,
			},
		},
		config = function()
			require('config/telescope')
		end
	},
	{
		'nvim-telescope/telescope-file-browser.nvim',
		dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
	},
	-- Useful plugin to show you pending keybinds.
	-- https://github.com/folke/which-key.nvim
	{
		'folke/which-key.nvim',
		event = "VeryLazy",
		init = function()
			vim.o.timeout = true
			vim.o.timeoutlen = 300
		end,
	},
}
