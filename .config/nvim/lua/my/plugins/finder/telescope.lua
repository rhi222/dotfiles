local telescopeConfig = require("telescope.config")
-- Clone the default Telescope configuration
local vimgrep_arguments = vim.list_extend({}, telescopeConfig.values.vimgrep_arguments)
-- I want to search in hidden/dot files.
table.insert(vimgrep_arguments, "--hidden")
-- I don't want to search in the `.git` directory.
table.insert(vimgrep_arguments, "--glob")
table.insert(vimgrep_arguments, "!**/.git/*")

local actions = require("telescope.actions")

-- config recipe
-- https://github.com/nvim-telescope/telescope.nvim/wiki/Configuration-Recipes
require("telescope").setup({
	defaults = {
		-- `hidden = true` is not supported in text grep commands.
		vimgrep_arguments = vimgrep_arguments,
		mappings = {
			n = {
				["q"] = actions.close,
			},
		},
		layout_strategy = "horizontal", -- horizontal, center, vertical, flex, cursor
		layout_config = {
			vertical = {
				width = 0.8,
				height = 0.8,
			},
			horizontal = {
				preview_width = 0.55,
			},
			cursor = {
				width = 0.8,
				height = 0.8,
				preview_width = 0.55,
			},
		},
		cache_picker = {
			num_pickers = 10,
		},
		sorting_strategy = "ascending",
	},
	pickers = {
		find_files = {
			-- `hidden = true` will still show the inside of `.git/` as it's not `.gitignore`d.
			find_command = { "rg", "--files", "--hidden", "--glob", "!**/.git/*" },
		},
	},
	extensions = {
		-- https://github.com/nvim-telescope/telescope-fzf-native.nvim
		fzf = {
			fuzzy = true, -- false will only do exact matching
			override_generic_sorter = true, -- override the generic sorter
			override_file_sorter = true, -- override the file sorter
			case_mode = "smart_case", -- or "ignore_case" or "respect_case"
		},
		smart_open = {
			disable_devicons = false,
		},
	},
})
-- Enable telescope fzf native, if installed
pcall(require("telescope").load_extension, "fzf")

-- https://github.com/fdschmidt93/telescope-egrepify.nvim
pcall(require("telescope").load_extension, "egrepify")
