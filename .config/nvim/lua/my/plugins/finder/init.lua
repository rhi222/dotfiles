local km = require("my.plugins.keymaps")
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
				"fdschmidt93/telescope-egrepify.nvim",
			},
		},
		keys = {
			-- https://minerva.mamansoft.net/Notes/%F0%9F%93%95telescope.nvim%E3%83%AC%E3%82%B7%E3%83%94 から拝借
			km.lazy_key(
				"finder",
				"telescope_find_files",
				":Telescope find_files<CR>",
				{ silent = true }
			),
			km.lazy_key("finder", "telescope_smart_open", ":Telescope smart_open<CR>", { silent = true }),
			km.lazy_key("finder", "telescope_live_grep", ":Telescope egrepify<CR>", { silent = true }),
			km.lazy_key(
				"finder",
				"telescope_fuzzy_find",
				":Telescope current_buffer_fuzzy_find<CR>",
				{ silent = true }
			),
			km.lazy_key("finder", "telescope_commands", ":Telescope commands<CR>", { silent = true }),
			km.lazy_key("finder", "telescope_cmd_history", ":Telescope command_history<CR>", { silent = true }),
			km.lazy_key("finder", "telescope_bookmarks", ":Telescope vim_bookmarks all<CR>", { silent = true }),
			km.lazy_key(
				"finder",
				"telescope_symbols",
				":Telescope lsp_dynamic_workspace_symbols<CR>",
				{ silent = true }
			),
			km.lazy_key(
				"finder",
				"telescope_git_status",
				":Telescope git_status<CR>",
				{ silent = true }
			),
			km.lazy_key("finder", "telescope_resume", ":Telescope resume<CR>", { silent = true }),
			km.lazy_key("finder", "telescope_buffers", ":Telescope buffers<CR>", { silent = true }),
			km.lazy_key("finder", "telescope_oldfiles", ":Telescope oldfiles<CR>", { silent = true }),
			km.lazy_key("finder", "telescope_help", ":Telescope help_tags<CR>", { silent = true }),
			km.lazy_key("finder", "telescope_diagnostics", ":Telescope diagnostics<CR>", { silent = true }),
		},
		config = function()
			require("my/plugins/finder/telescope")
		end,
	},
	-- https://github.com/danielfalk/smart-open.nvim
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
			km.lazy_key("finder", "fzf_grep", "<cmd>lua require('fzf-lua').grep()<CR>", { silent = true }),
		},
		config = function()
			require("my/plugins/finder/fzf-lua")
		end,
	},
	-- https://github.com/nvim-mini/mini.files
	{
		"echasnovski/mini.files",
		keys = {
			km.lazy_key("finder", "mini_files_open", function()
				local buf_name = vim.api.nvim_buf_get_name(0)
				local path = vim.fn.fnamemodify(buf_name, ":p:h")
				require("mini.files").open(path)
			end, { silent = true }),
		},
		config = function()
			require("my/plugins/finder/mini-files")
		end,
	},
}
