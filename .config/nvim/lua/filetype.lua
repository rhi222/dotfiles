-- https://neovim.discourse.group/t/vim-filetype-add-with-the-filename-option-seems-not-working/3338/4
vim.filetype.add({
  pattern = {
    [".*sqltmpl"] = "sql",
  },
})

local M = {}

local function set_indent(tab_length, is_hard_tab)
	if is_hard_tab then
		vim.bo.expandtab = false
	else
		vim.bo.expandtab = true
	end

	vim.bo.shiftwidth = tab_length
	vim.bo.softtabstop = tab_length
	vim.bo.tabstop = tab_length
end

M.help = function()
	vim.api.nvim_buf_set_keymap(0, "n", "q", "ZZ", { noremap = true })
end

M.graphql = function()
	set_indent(4, false)
end

M.python = function()
	set_indent(4, true)
end

M.typescript = function()
	set_indent(4, true)
end

M.typescriptreact = function()
	set_indent(4, true)
end

M.yaml = function()
	set_indent(2, true)
end

return setmetatable(M, {
	__index = function()
		return function()
			print("Unexpected filetype!")
			set_indent(4, true)
		end
	end,
})
