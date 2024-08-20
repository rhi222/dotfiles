-- https://neovim.discourse.group/t/vim-filetype-add-with-the-filename-option-seems-not-working/3338/4
vim.filetype.add({
	pattern = {
		[".*sqltmpl"] = "sql",
		[".env.*"] = "sh",
	},
})

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
local function setup_indent(settings)
	vim.bo.shiftwidth = settings.tab_length
	vim.bo.softtabstop = settings.tab_length
	vim.bo.tabstop = settings.tab_length
	vim.bo.expandtab = not settings.is_hard_tab
	vim.bo.autoindent = settings.is_auto_indent
end

local M = {}

M.help = function()
	vim.api.nvim_buf_set_keymap(0, "n", "q", "ZZ", { noremap = true })
end

-- よく使われる設定をグループ化し、一行で複数のファイルタイプを設定
for _, ft in ipairs({
	"graphql",
	"javascript",
	"json",
	"lua",
	"markdown",
	"sh",
	"typescript",
	"typescriptreact",
	"xml",
}) do
	M[ft] = function()
		setup_indent({
			tab_length = 4,
			is_hard_tab = true,
			is_auto_indent = true,
		})
	end
end

for _, ft in ipairs({
	"python",
	"rust",
	"dockerfile",
}) do
	M[ft] = function()
		setup_indent({
			tab_length = 4,
			is_hard_tab = false,
			is_auto_indent = true,
		})
	end
end

for _, ft in ipairs({
	"gitcommit",
	"yaml",
}) do
	M[ft] = function()
		setup_indent({
			tab_length = 2,
			is_hard_tab = true,
			is_auto_indent = true,
		})
	end
end

local my_filetype = setmetatable(M, {
	__index = function()
		return function()
			-- print("Unexpected filetype!")
			setup_indent({
				tab_length = 4,
				is_hard_tab = true,
				is_auto_indent = true,
			})
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
