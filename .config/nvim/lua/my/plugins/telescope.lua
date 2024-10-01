local telescopeConfig = require("telescope.config")
-- Clone the default Telescope configuration
local vimgrep_arguments = { unpack(telescopeConfig.values.vimgrep_arguments) }
-- I want to search in hidden/dot files.
table.insert(vimgrep_arguments, "--hidden")
-- I don't want to search in the `.git` directory.
table.insert(vimgrep_arguments, "--glob")
table.insert(vimgrep_arguments, "!**/.git/*")

-- https://github.com/nvim-telescope/telescope.nvim#usage
-- local builtin = require("telescope.builtin")
-- vim.keymap.set("n", "<C-p>", builtin.find_files, {})
-- grepはfzf-luaを利用
-- https://github.com/ibhagwan/fzf-lua
-- vim.keymap.set("n", "<C-g>", builtin.live_grep, {})
-- vim.keymap.set("n", "<C-g>", builtin.grep_string, {})
-- vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
-- vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})

-- https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/103
local actions = require("telescope.actions")
local fb_actions = require("telescope").extensions.file_browser.actions

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
			center = {
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
		-- neovim nightlyだとresults are not display when filtering
		-- いずれ削除してもよい設定
		-- https://github.com/nvim-telescope/telescope.nvim/issues/2667
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
		file_browser = {
			select_buffer = true,
			path = vim.loop.cwd(),
			cwd = vim.loop.cwd(),
			cwd_to_path = true,
			no_ignore = true,
			hijack_netrw = true,
			-- theme = "ivy", -- ivy, dropdown, cursor
			initial_mode = "normal",
			mappings = {
				["i"] = {
					-- your custom insert mode mappings
				},
				["n"] = {
					-- your custom normal mode mappings
					["h"] = fb_actions.goto_parent_dir,
					["l"] = actions.select_default,
					["q"] = actions.close,
				},
			},
		},
	},
})
-- Enable telescope fzf native, if installed
pcall(require("telescope").load_extension, "fzf")

-- https://github.com/nvim-telescope/telescope-file-browser.nvim
require("telescope").load_extension("file_browser")

-- https://github.com/fdschmidt93/telescope-egrepify.nvim
pcall(require("telescope").load_extension, "egrepify")
