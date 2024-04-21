-- https://neovim.discourse.group/t/vim-filetype-add-with-the-filename-option-seems-not-working/3338/4
vim.filetype.add({
	pattern = {
		[".*sqltmpl"] = "sql",
	},
})

local M = {}

-- tab/indent
-- https://qiita.com/ysn/items/f4fc8f245ba50d5fb8b0
-- https://vim-jp.org/vimdoc-ja/indent.html
-- NOTE:
-- expandtab: タブをスペースに変換するかどうか。trueなら変換しソフトタブ
-- shiftwidth: インデントの見た目の空白数の設定値
-- softtabstop: インサートモード時に、<Tab>キー、<BS>キーの入力に対する見た目上の空白数を設定する
-- tabstop: タブ制御文字(\0x09 in ascii)に対する見た目上の空白数を設定する
-- autoindent: 一つ前の行に基づくインデント
-- smartindent: C言語のような構造化された言語のインデント
local function set_indent(tab_length, is_hard_tab, is_auto_indent)
	if is_hard_tab then
		vim.bo.expandtab = false
	else
		vim.bo.expandtab = true
	end

	if is_auto_indent then
		vim.bo.autoindent = false
	else
		vim.bo.autoindent = true
	end

	vim.bo.shiftwidth = tab_length
	vim.bo.softtabstop = tab_length
	vim.bo.tabstop = tab_length
end

M.help = function()
	vim.api.nvim_buf_set_keymap(0, "n", "q", "ZZ", { noremap = true })
end

M.graphql = function()
	set_indent(4, false, true)
end

M.python = function()
	set_indent(4, true, true)
end

M.typescript = function()
	set_indent(4, false, true)
end

M.typescriptreact = function()
	set_indent(4, false, true)
end

M.yaml = function()
	set_indent(2, false, true)
end

M.gitcommit = function()
	set_indent(2, false, true)
end

M.sh = function()
	set_indent(4, false, true)
end

local my_filetype = setmetatable(M, {
	__index = function()
		return function()
			print("Unexpected filetype!")
			-- NOTE: デフォルトはタブインデント
			set_indent(4, false, true)
		end
	end,
})

vim.api.nvim_create_augroup("vimrc_augroup", {})
vim.api.nvim_create_autocmd("FileType", {
	group = "vimrc_augroup",
	pattern = "*",
	callback = function(args)
		my_filetype[args.match]()
	end,
})
