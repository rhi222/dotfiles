return {
	{
		"nvim-lualine/lualine.nvim",
		config = function()
			require("my/plugins/lualine")
		end,
	},
	{
		"lewis6991/gitsigns.nvim",
		config = function()
			require("my/plugins/gitsigns")
		end,
	},
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		config = function()
			require("my/plugins/indent-blankline")
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter",
		config = function()
			require("my/plugins/nvim-treesitter")
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
	-- copilot.lua使ってみたいが、keymapがうまく出来ずに保留
	-- {
	-- 	'zbirenbaum/copilot.lua',
	-- 	config = function()
	-- 		require('my/plugins/copilot')
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
			require("my/plugins/nvim-cmp")
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
					require("my/plugins/nvim-lspconfig")
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
			require("my/plugins/mason")
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
			require("my/plugins/formatter")
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
			require("my/plugins/telescope")
		end,
	},
	{
		"ibhagwan/fzf-lua",
		-- optional for icon support
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("my/plugins/fzf-lua")
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
			require("my/plugins/vim-quickhl")
		end,
	},
	{
		"phaazon/hop.nvim",
		config = function()
			require("my/plugins/hop")
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
			require("my/plugins/rest-nvim")
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
	-- fold
	-- https://github.com/chrisgrieser/.my/plugins/blob/main/nvim/lua/plugins/folding-plugins.lua#L7
	{
		"kevinhwang91/nvim-ufo",
		dependencies = "kevinhwang91/promise-async",
		event = "VimEnter", -- needed for folds to load in time and comments closed
		keys = {
			-- stylua: ignore start
			{ "zm", function() require("ufo").closeAllFolds() end, desc = "󱃄 Close All Folds" },
			{ "zr", function() require("ufo").openFoldsExceptKinds { "comment", "imports" } end, desc = "󱃄 Open All Regular Folds" },
			{ "zR", function() require("ufo").openFoldsExceptKinds {} end, desc = "󱃄 Open All Folds" },
			{ "z1", function() require("ufo").closeFoldsWith(1) end, desc = "󱃄 Close L1 Folds" },
			{ "z2", function() require("ufo").closeFoldsWith(2) end, desc = "󱃄 Close L2 Folds" },
			{ "z3", function() require("ufo").closeFoldsWith(3) end, desc = "󱃄 Close L3 Folds" },
			{ "z4", function() require("ufo").closeFoldsWith(4) end, desc = "󱃄 Close L4 Folds" },
			-- stylua: ignore end
		},
		init = function()
			-- INFO fold commands usually change the foldlevel, which fixes folds, e.g.
			-- auto-closing them after leaving insert mode, however ufo does not seem to
			-- have equivalents for zr and zm because there is no saved fold level.
			-- Consequently, the vim-internal fold levels need to be disabled by setting
			-- them to 99
			vim.opt.foldlevel = 99
			vim.opt.foldlevelstart = 99
		end,
		opts = {
			provider_selector = function(_, ft, _)
				-- INFO some filetypes only allow indent, some only LSP, some only
				-- treesitter. However, ufo only accepts two kinds as priority,
				-- therefore making this function necessary :/
				local lspWithOutFolding = { "markdown", "sh", "css", "html", "python", "typescript", "tsx", "lua" }
				if vim.tbl_contains(lspWithOutFolding, ft) then
					return { "treesitter", "indent" }
				end
				return { "lsp", "indent" }
			end,
			-- when opening the buffer, close these fold kinds
			-- use `:UfoInspect` to get available fold kinds from the LSP
			close_fold_kinds_for_ft = {
				default = { "imports", "comment" },
			},
			open_fold_hl_timeout = 800,
			fold_virt_text_handler = function(virtText, lnum, endLnum, width, truncate)
				local hlgroup = "NonText"
				local newVirtText = {}
				local suffix = "    " .. tostring(endLnum - lnum)
				local sufWidth = vim.fn.strdisplaywidth(suffix)
				local targetWidth = width - sufWidth
				local curWidth = 0
				for _, chunk in ipairs(virtText) do
					local chunkText = chunk[1]
					local chunkWidth = vim.fn.strdisplaywidth(chunkText)
					if targetWidth > curWidth + chunkWidth then
						table.insert(newVirtText, chunk)
					else
						chunkText = truncate(chunkText, targetWidth - curWidth)
						local hlGroup = chunk[2]
						table.insert(newVirtText, { chunkText, hlGroup })
						chunkWidth = vim.fn.strdisplaywidth(chunkText)
						if curWidth + chunkWidth < targetWidth then
							suffix = suffix .. (" "):rep(targetWidth - curWidth - chunkWidth)
						end
						break
					end
					curWidth = curWidth + chunkWidth
				end
				table.insert(newVirtText, { suffix, hlgroup })
				return newVirtText
			end,
		},
	},
}
