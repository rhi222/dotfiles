-- https://neovim.discourse.group/t/vim-filetype-add-with-the-filename-option-seems-not-working/3338/4
vim.filetype.add({
	extension = {
		tsv = "tsv",
		puml = "plantuml",
		plantuml = "plantuml",
		pu = "plantuml",
	},
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

M.markdown = function()
	setup_indent({
		tab_length = 4,
		is_hard_tab = true,
		is_auto_indent = true,
	})
	-- チェックボックス入力補助: cb + スペース → - [ ]
	vim.cmd("iabbrev <buffer> cb - [ ]")
	-- チェックボックストグル: <leader>x で [ ] ↔ [x] 切り替え
	vim.keymap.set("n", "<leader>x", function()
		local line = vim.api.nvim_get_current_line()
		if line:match("%[x%]") then
			line = line:gsub("%[x%]", "[ ]", 1)
		elseif line:match("%[ %]") then
			line = line:gsub("%[ %]", "[x]", 1)
		end
		vim.api.nvim_set_current_line(line)
	end, { buffer = 0, desc = "Toggle checkbox" })
end

-- よく使われる設定をグループ化し、一行で複数のファイルタイプを設定
for _, ft in ipairs({
	"graphql",
	"javascript",
	"json",
	"lua",
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

-- TSVファイルでタブ文字を可視化
vim.api.nvim_create_autocmd("FileType", {
	group = "vimrc_augroup",
	pattern = "tsv",
	callback = function()
		vim.opt_local.list = true
		vim.opt_local.listchars = { tab = "│ ", trail = "·" }
	end,
})

-- rest.nvimのformat
-- https://github.com/rest-nvim/rest.nvim/issues/414#issuecomment-2308721227
vim.api.nvim_create_autocmd("FileType", {
	pattern = "json",
	callback = function(ev)
		vim.bo[ev.buf].formatprg = "jq"
	end,
})

-- herdr: nvim が動いているペインを自動記録する。
-- reboot 後に fish の `he` ラッパーがこのマーカーを読んで、該当ペインで nvim を復元起動する
-- （tmux-resurrect の @resurrect-processes 相当。手動ラベル付けは不要）。
-- 1ペイン=1ファイルにすることで複数 nvim 間の読み書き競合を避ける。
-- シャットダウン時は VimLeavePre が走らずマーカーが残る＝「nvim が動いていたペイン」が残る。
do
	local herdr_pane = vim.env.HERDR_PANE_ID
	if herdr_pane and herdr_pane ~= "" then
		local state_dir = (vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state")) .. "/herdr-nvim"
		local marker = state_dir .. "/" .. herdr_pane
		local grp = vim.api.nvim_create_augroup("herdr_nvim_registry", {})
		vim.api.nvim_create_autocmd("VimEnter", {
			group = grp,
			callback = function()
				vim.fn.mkdir(state_dir, "p")
				-- 内容は cwd（デバッグ用）。ファイル名がペイン ID。
				vim.fn.writefile({ vim.fn.getcwd() }, marker)
			end,
		})
		vim.api.nvim_create_autocmd("VimLeavePre", {
			group = grp,
			callback = function()
				-- :q 等の通常終了では削除する。OS shutdown やペイン終了時は
				-- SIGTERM/SIGHUP により vim.v.dying > 0 になるため、復元用に残す。
				if vim.v.dying == 0 then
					vim.fn.delete(marker)
				end
			end,
		})
	end
end
