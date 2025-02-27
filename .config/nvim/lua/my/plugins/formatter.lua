-- https://github.com/mhartington/formatter.nvim
-- Provides the Format, FormatWrite, FormatLock, and FormatWriteLock commands
local formatter_prettier = { require("formatter.defaults.prettier") }
local formatter_biome = { require("formatter.defaults.biome") }
require("formatter").setup({
	-- Enable or disable logging
	logging = true,
	-- Set the log level
	log_level = vim.log.levels.WARN,
	-- All formatter configurations are opt-in
	filetype = {
		javascript = formatter_prettier,
		javascriptreact = formatter_prettier,
		typescript = formatter_biome,
		typescriptreact = formatter_biome,
		json = {
			require("formatter.filetypes.json").prettier,
		},
		json5 = {
			require("formatter.filetypes.json").prettier,
		},
		python = {
			require("formatter.filetypes.python").ruff,
		},
		lua = {
			require("formatter.filetypes.lua").stylua,
		},
		xml = {
			require("formatter.filetypes.xml").xmlformat,
		},
		bash = {
			require("formatter.filetypes.sh").shfmt,
		},
		html = {
			require("formatter.filetypes.html").prettier,
		},
		sql = {
			-- https://github.com/mhartington/formatter.nvim/blob/master/lua/formatter/filetypes/sql.lua
			-- require("formatter.filetypes.sql").sqlfluff(),
			-- 本体の実装だと、--dialectの指定ができないのでoverwridte
			function()
				return {
					exe = "sqlfluff",
					args = {
						"format",
						"--dialect postgres",
						"--disable-progress-bar",
						"--nocolor",
						"-",
					},
					stdin = true,
					ignore_exitcode = false,
				}
			end,
		},
		-- Use the special '*' filetype for defining formatter configurations on any filetype
		["*"] = {
			require("formatter.filetypes.any").remove_trailing_whitespace,
		},
	},
})
