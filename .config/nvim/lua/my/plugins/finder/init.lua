return {
	{
		"nvim-telescope/telescope.nvim",
		tag = "v0.2.1", -- 公式READMEがtag指定推奨
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
			-- https://minerva.mamansoft.net/Notes/%F0%9F%93%95telescope.nvim%E3%83%AC%E3%82%B7%E3%83%94 から拝借
			{ "<C-p>f", ":Telescope find_files find_command=rg,--files,--hidden,--glob,!*.git <CR>", silent = true },
			-- { "<C-p>z", ":Telescope frecency<CR>", silent = true },
			{ "<C-p>e", ":Telescope smart_open<CR>", silent = true },
			{ "<C-p>g", ":Telescope live_grep<CR>", silent = true },
			{ "<C-p>l", ":Telescope current_buffer_fuzzy_find<CR>", silent = true },
			{ "<C-p>p", ":Telescope commands<CR>", silent = true },
			{ "<C-p>:", ":Telescope command_history<CR>", silent = true },
			{ "<C-p>m", ":Telescope vim_bookmarks all<CR>", silent = true },
			{ "<C-p>s", ":Telescope lsp_dynamic_workspace_symbols<CR>", silent = true },
			{ "<C-p>c", ":lua require'telescope.builtin'.git_status{}<CR>", silent = true },
		},
		config = function()
			require("my/plugins/finder/telescope")
		end,
	},
	-- https://github.com/danielfalk/smart-open.nvim
	-- https://minerva.mamansoft.net/%F0%9F%93%98Articles/%F0%9F%93%98%E3%81%82%E3%81%BE%E3%82%8A%E7%B4%B9%E4%BB%8B%E3%81%95%E3%82%8C%E3%81%A6%E3%81%84%E3%81%AA%E3%81%84%E3%81%91%E3%81%A9+%E3%81%8B%E3%81%91%E3%81%8C%E3%81%88%E3%81%AE%E3%81%AA%E3%81%84Neovim%E3%83%97%E3%83%A9%E3%82%B0%E3%82%A4%E3%83%B3%E3%81%9F%E3%81%A1#smart-open.nvim
	{
		"danielfalk/smart-open.nvim",
		branch = "0.2.x",
		event = "VeryLazy",
		config = function()
			require("telescope").load_extension("smart_open")
		end,
		dependencies = {
			"kkharji/sqlite.lua",
			-- Only required if using match_algorithm fzf
			{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
			-- Optional.  If installed, native fzy will be used when match_algorithm is fzy
			{ "nvim-telescope/telescope-fzy-native.nvim" },
		},
	},
	{
		"ibhagwan/fzf-lua",
		-- optional for icon support
		dependencies = { "nvim-tree/nvim-web-devicons" },
		keys = {
			{ "<c-g>", "<cmd>lua require('fzf-lua').grep()<CR>", mode = "n", silent = true },
			-- note: telescopeのsmart-openが賢そうなので移行してみる
			-- { "<c-p>", "<cmd>lua require('fzf-lua').files()<CR>", mode = "n", silent = true },
		},
		config = function()
			require("my/plugins/finder/fzf-lua")
		end,
	},
}
