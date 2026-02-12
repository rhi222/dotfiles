-- https://github.com/zbirenbaum/copilot.lua
local km = require("my.plugins.keymaps")
local accept_key = km.get("completion", "copilot_accept")
local next_key = km.get("completion", "copilot_next")
local prev_key = km.get("completion", "copilot_prev")
local dismiss_key = km.get("completion", "copilot_dismiss")

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
			accept = accept_key,
			accept_word = false,
			accept_line = false,
			next = next_key,
			prev = prev_key,
			dismiss = dismiss_key,
		},
	},
})
