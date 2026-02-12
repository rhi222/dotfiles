-- https://github.com/zbirenbaum/copilot.lua
require("copilot").setup({
	filetypes = {
		-- allow specific filetype
		javascript = true,
		typescript = true,
		typescriptreact = true,
		python = true,
		markdown = true,
		lua = true,
		sql = true,
		txt = true,
		sh = function()
			if string.match(vim.fs.basename(vim.api.nvim_buf_get_name(0)), "^%.env.*") then
				-- disable for .env files
				return false
			end
			return true
		end,
		["*"] = false, -- disable for all other filetypes and ignore default `filetypes`
	},
	suggestion = {
		enabled = true,
		auto_trigger = true,
		keymap = {
			accept = "<C-y>",
			accept_word = false,
			accept_line = false,
			next = "<C-l>",
			prev = "<C-h>",
			dismiss = "<C-]>",
		},
	},
})
