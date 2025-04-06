-- TODO: https://github.com/skanehira/dotfiles/blob/master/vim/lua/my/plugins/list.lua を参考にファイル分割したい
-- NOTE: eventのdocument
-- nvim events: https://gist.github.com/dtr2300/2f867c2b6c051e946ef23f92bd9d1180
-- lazy.nvim events: https://github.com/folke/lazy.nvim/blob/main/doc/lazy.nvim.txt#L1050-L1070
-- NOTE: vimのmode:
-- https://neovim.io/doc/user/intro.html#_modes,-introduction
-- `:help map-table`で確認可能
-- NOTE: keysのdocument
-- https://github.com/folke/lazy.nvim/blob/main/doc/lazy.nvim.txt#L519-L568
-- FIXME: key map再考
-- https://zenn.dev/vim_jp/articles/2023-05-19-vim-keybind-philosophy
-- https://zenn.dev/nil2/articles/802f115673b9ba
-- https://maku77.github.io/vim/keymap/current-map.html
-- https://stackoverflow.com/questions/2239226/saving-output-of-map-in-vim
return {
	-- TODO: lualineがalacrittyで表示崩れ。代替を探す
	-- https://github.com/yutkat/my-neovim-pluginlist/blob/main/statusline.md
	{
		"nvim-lualine/lualine.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			require("my/plugins/lualine")
		end,
	},
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		event = "VeryLazy",
		config = function()
			require("my/plugins/indent-blankline")
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			require("my/plugins/nvim-treesitter")
		end,
		dependencies = {
			"nvim-treesitter/playground",
		},
	},
	-- colorscheme
	{
		"rebelot/kanagawa.nvim",
		lazy = true,
		config = function()
			require("my/plugins/kanagawa")
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
			require("my/plugins/tokyonight")
		end,
	},
	-- nvim-treesitterのsyntax highlightが絶妙に見にくかったのでtokyonightから乗り換え
	-- https://github.com/rockerBOO/awesome-neovim?tab=readme-ov-file#tree-sitter-supported-colorscheme からpickした
	{
		"Mofiqul/vscode.nvim",
		config = function()
			require("my/plugins/vscode")
		end,
	},
	-- copilot: 処理が早く、最近のプラグインとの統合が容易(と言っている)ため、.vimでなく.luaを採用
	-- {
	-- 	"github/copilot.vim",
	-- 	event = "InsertEnter",
	-- },
	{
		"zbirenbaum/copilot.lua",
		event = "InsertEnter",
		config = function()
			require("my/plugins/copilot")
		end,
	},
	{
		"CopilotC-Nvim/CopilotChat.nvim",
		event = "VeryLazy",
		dependencies = {
			{ "zbirenbaum/copilot.lua" }, -- or github/copilot.vim
			{ "nvim-lua/plenary.nvim" }, -- for curl, log wrapper
			{ "nvim-telescope/telescope.nvim" },
		},
		build = "make tiktoken",
		config = function()
			require("my/plugins/copilot-chat")
		end,
		-- See Commands section for default commands if you want to lazy load on them
	},
	{
		"zbirenbaum/copilot-cmp",
		config = function()
			require("my/plugins/copilot-cmp")
		end,
	},
	{
		"hrsh7th/nvim-cmp",
		event = { "InsertEnter", "CmdlineEnter" },
		dependencies = {
			-- TODO: 要精査
			"hrsh7th/cmp-nvim-lsp", --LSPを補完ソースに
			"hrsh7th/cmp-buffer", --bufferを補完ソースに
			"hrsh7th/cmp-cmdline", -- vimのコマンド
			"hrsh7th/cmp-path", --pathを補完ソースに
			"hrsh7th/vim-vsnip", --スニペットエンジン
			-- 'hrsh7th/cmp-vsnip', --スニペットを補完ソースに
			"onsails/lspkind.nvim", --補完欄にアイコンを表示
			"zbirenbaum/copilot-cmp", --copilotを補完ソースに
		},
		config = function()
			require("my/plugins/nvim-cmp")
		end,
	},
	-- LSP
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
		config = function()
			require("my/plugins/mason")
		end,
	},
	{
		"williamboman/mason-lspconfig.nvim",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			"williamboman/mason.nvim",
			"neovim/nvim-lspconfig",
		},
		config = function()
			require("my/plugins/mason-lspconfig")
		end,
	},
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			-- Useful status updates for LSP
			-- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
			{ "j-hui/fidget.nvim", tag = "v1.6.1", opts = {} },
			-- Additional lua configuration, makes nvim stuff amazing!
			{ "folke/neodev.nvim", opts = {} },
		},
		config = function()
			require("my/plugins/nvim-lspconfig")
		end,
	},
	-- formatter: star数の多いconform.nvimに移行
	{
		"stevearc/conform.nvim",
		config = function()
			require("my/plugins/conform")
		end,
		event = { "BufWritePre" },
		cmd = {
			"ConformInfo",
			"Format",
			"FormatDisable",
			"FormatEnable",
		},
	},
	--[[ {
		"mhartington/formatter.nvim",
		cmd = {
			"Format",
			"FormatWrite",
			"FormatLock",
			"FormatWriteLock",
		},
		config = function()
			require("my/plugins/formatter")
		end,
	}, ]]
	-- finder
	{
		"nvim-telescope/telescope.nvim",
		tag = "0.1.8", -- 公式READMEがtag指定推奨
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
			{
				"fdschmidt93/telescope-egrepify.nvim",
			},
		},
		keys = {
			-- open file_browser with the path of the current buffer
			{
				"<space>f",
				":Telescope file_browser layout_strategy=center path=%:p:h select_buffer=true<CR>",
				mode = "n",
				silent = true,
				noremap = true,
			},
		},
		config = function()
			require("my/plugins/telescope")
		end,
	},
	{
		"ibhagwan/fzf-lua",
		-- optional for icon support
		dependencies = { "nvim-tree/nvim-web-devicons" },
		keys = {
			{ "<c-g>", "<cmd>lua require('fzf-lua').grep()<CR>", mode = "n", silent = true },
			-- note: fzf-lua updateで動かなくなったのでtelescopeに移行
			{ "<c-p>", "<cmd>lua require('fzf-lua').files()<CR>", mode = "n", silent = true },
		},
		config = function()
			require("my/plugins/fzf-lua")
		end,
	},
	-- git
	{
		"lewis6991/gitsigns.nvim",
		config = function()
			require("my/plugins/gitsigns")
		end,
	},
	{
		"NeogitOrg/neogit",
		dependencies = {
			"nvim-lua/plenary.nvim", -- required
			"sindrets/diffview.nvim", -- optional - Diff integration
			"nvim-telescope/telescope.nvim", -- optional
		},
		keys = {
			{ "<leader>g", "<cmd>lua require('neogit').open()<CR>", mode = "n", desc = "neogit", noremap = true },
		},
		config = function()
			require("my/plugins/neogit")
		end,
	},
	{
		"nvim-tree/nvim-web-devicons",
	},
	-- highlight
	{
		"kevinhwang91/nvim-hlslens",
		event = "VeryLazy",
		config = function()
			require("my/plugins/nvim-hlslens")
		end,
	},
	{
		"t9md/vim-quickhl",
		keys = {
			{
				"<leader>m",
				"<Plug>(quickhl-manual-this)",
				mode = "n",
				desc = "quickhl manual this",
				noremap = true,
			},
		},
		cmd = {
			"QuickhlManualAdd",
		},
		config = function()
			require("my/plugins/vim-quickhl")
		end,
	},
	-- easymotion
	{
		-- NOTE: 本家はneovim 0.11対応しないためforkを採用
		-- "phaazon/hop.nvim",
		"smoka7/hop.nvim",
		version = "*",
		keys = {
			{ "<leader>j", ":HopWord<CR>", mode = "n", desc = "hop word", noremap = true },
		},
		config = function()
			require("my/plugins/hop")
		end,
	},
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		opts = {},
		-- stylua: ignore
		keys = {
			{ "gs", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
			{ "gS", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
			{ "gr", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
			{ "gR", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
			{ "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
		},
	},
	-- http client
	{
		"rest-nvim/rest.nvim",
		ft = "http",
		tag = "v3.12.0",
		config = function()
			require("my/plugins/_rest-nvim")
		end,
		keys = {
			{ "<C-e>", "<cmd>Rest run<CR>", mode = "n", desc = "Run rest command" },
		},
	},
	-- markdown preview
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		ft = { "markdown" },
		build = function()
			vim.fn["mkdp#util#install"]()
		end,
		config = function()
			require("my/plugins/markdown-preview")
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
	-- other
	-- filetype.luaと衝突するが、チーム開発する上でPJごとの設定を都度しなくて良いので、こちらを優先
	-- automatically adjusts 'shiftwidth' and 'expandtab' heuristically based on the current file
	{
		"tpope/vim-sleuth",
	},
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
	},
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		opts = {}, -- this is equalent to setup({}) function
	},
	-- NOTE: folodingをnvim-ufo -> nvim-treesitterに変えてみる
	-- - ufoの誤作動がきになる
	-- - nvim-treesitterで十分な機能に見え、ufoをinstallしなくてよさそう
	-- {
	-- 	"kevinhwang91/nvim-ufo",
	-- 	dependencies = {
	-- 		"kevinhwang91/promise-async",
	-- 	},
	-- 	keys = {
	-- 		{ "zR", "<cmd>lua require('ufo').openAllFolds()<CR>", mode = "n", desc = "open all folds" },
	-- 		{ "zM", "<cmd>lua require('ufo').closeAllFolds()<CR>", mode = "n", desc = "close all folds" },
	-- 	},
	-- 	config = function()
	-- 		require("my/plugins/nvim-ufo")
	-- 	end,
	-- },
	{
		"numToStr/Comment.nvim",
		event = "BufRead",
		config = function()
			require("my/plugins/comment")
		end,
	},
	{
		"folke/todo-comments.nvim",
		event = "BufRead",
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			require("my/plugins/todo-comments")
		end,
	},
}

-- NOTE: plugin一覧
-- https://github.com/yutkat/my-neovim-pluginlist
