-- https://github.com/mhartington/formatter.nvim
-- -- Utilities for creating configurations
-- local util = require("formatter.util")

-- Provides the Format, FormatWrite, FormatLock, and FormatWriteLock commands
local formatter_prettier = { require("formatter.defaults.prettier") }
require("formatter").setup({
	-- Enable or disable logging
	logging = true,
	-- Set the log level
	log_level = vim.log.levels.WARN,
	-- All formatter configurations are opt-in
	filetype = {
		javascript = formatter_prettier,
		javascriptreact = formatter_prettier,
		typescript = formatter_prettier,
		typescriptreact = formatter_prettier,
		json = {
			require("formatter.filetypes.json").prettier,
		},
		python = {
			require("formatter.filetypes.python").black,
		},
		lua = {
			require("formatter.filetypes.lua").stylua,
		},

		-- Use the special '*' filetype for defining formatter configurations on
		-- any filetype
		["*"] = {
			-- 'formatter.filetypes.any' defines default configurations for any
			-- filetype
			require("formatter.filetypes.any").remove_trailing_whitespace,
		},
	},
})
