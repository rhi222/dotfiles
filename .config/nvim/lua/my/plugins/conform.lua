-- https://github.com/stevearc/conform.nvim
-- Conform will run multiple formatters sequentially, run the first available formatter
local formatter_js = { "biome", "prettier", stop_after_first = true }
require("conform").setup({
	formatters_by_ft = {
		bash = { "shfmt" },
		html = { "prettier" },
		javascript = formatter_js,
		javascriptreact = formatter_js,
		json = { "prettier" },
		json5 = { "prettier" },
		lua = { "stylua" },
		python = { "ruff", "black", stop_after_first = true },
		rust = { "rustfmt", lsp_format = "fallback" },
		sql = { "sqlfluff" },
		typescript = formatter_js,
		typescriptreact = formatter_js,
		xml = { "xmlformat" },
		-- Use the "_" filetype to run formatters on filetypes that don't
		-- have other formatters configured.
		["_"] = { "trim_whitespace" },
	},
})

-- https://github.com/stevearc/conform.nvim/blob/master/doc/recipes.md#format-command
vim.api.nvim_create_user_command("Format", function(args)
	local range = nil
	if args.count ~= -1 then
		local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
		range = {
			start = { args.line1, 0 },
			["end"] = { args.line2, end_line:len() },
		}
	end
	require("conform").format({ async = true, lsp_format = "fallback", range = range })
end, { range = true })
