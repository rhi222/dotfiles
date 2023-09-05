-- https://github.com/zbirenbaum/copilot.lua
require('copilot').setup({
	enabled = true,
	filetypes = {
		javascript = true, -- allow specific filetype
		typescript = true, -- allow specific filetype
		markdown = true,
		sh = function ()
			if string.match(vim.fs.basename(vim.api.nvim_buf_get_name(0)), '^%.env.*') then
				-- disable for .env files
				return false
			end
			return true
		end,	
		["*"] = false, -- disable for all other filetypes and ignore default `filetypes`
	},
	suggestion = {
		auto_trigger = true,
		keymap = {
			-- TODO: 通常のtabが効かなくなる
			accept = "<tab>",
		},
	},
})
