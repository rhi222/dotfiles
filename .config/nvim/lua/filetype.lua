-- https://neovim.discourse.group/t/vim-filetype-add-with-the-filename-option-seems-not-working/3338/4
vim.filetype.add({
	pattern = {
		[".*sqltmpl"] = "sql",
	},
})

local M = {}

-- tab/indent
-- https://qiita.com/ysn/items/f4fc8f245ba50d5fb8b0
-- https://qiita.com/ysn/items/f4fc8f245ba50d5fb8b0
-- NOTE:
-- expandtab: タブをスペースに変換するかどうか。trueなら変換しソフトタブ
-- shiftwidth: インデントの見た目の空白数の設定値
-- softtabstop: インサートモード時に、<Tab>キー、<BS>キーの入力に対する見た目上の空白数を設定する
-- tabstop: タブ制御文字(\0x09 in ascii)に対する見た目上の空白数を設定する
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
	set_indent(4, false)
end

M.typescriptreact = function()
	set_indent(4, false)
end

M.yaml = function()
	set_indent(2, false)
end

M.gitcommit = function()
	set_indent(2, false)
end

M.sh = function()
	set_indent(4, false)
end

return setmetatable(M, {
	__index = function()
		return function()
			-- print("Unexpected filetype!")
			-- NOTE: デフォルトはタブインデント
			set_indent(4, false)
		end
	end,
})
