-- require nvim v0.9.0 or later
-- -------------------- general mapping {{{
vim.scriptencoding = "utf-8"
vim.o.number = true
vim.o.tabpagemax = 50
-- indent
-- filetype.luaで設定しているのでコメントアウト
-- vim.o.tabstop = 4
-- vim.o.softtabstop = 4
-- vim.o.shiftwidth = 4
vim.o.autoindent = true
vim.o.smartindent = true
-- search
vim.o.incsearch = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.hlsearch = true
-- https://qiita.com/shiena/items/3f51a2c0b4722427e430
vim.o.cursorline = true
vim.o.cursorcolumn = true
-- https://zenn.dev/shougo/articles/set-cmdheight-0
vim.o.cmdheight = 0
-- clipboard
-- https://zenn.dev/koxya/articles/b71047cd88303b
-- https://zenn.dev/renoinn/scraps/f64fe35a81b753
vim.opt.clipboard = "unnamedplus"
if vim.fn.has("wsl") then
	vim.g.clipboard = {
		name = "win32yank-wsl",
		copy = {
			["+"] = "win32yank.exe -i --crlf",
			["*"] = "win32yank.exe -i --crlf",
		},
		paste = {
			["+"] = "win32yank.exe -o --crlf",
			["*"] = "win32yank.exe -o --crlf",
		},
		cache_enable = 0,
	}
end
-- https://github.com/volta-cli/volta/issues/866
vim.g.node_host_prog = vim.call("system", 'volta which neovim-node-host | tr -d "\n"')
vim.g.python_host_prog = vim.call("system", 'which python2 | tr -d "\n"')
vim.g.python3_host_prog = vim.call("system", 'which python3 | tr -d "\n"')
-- }}} -------------------------------

-- -------------------- key mapping {{{
vim.g.mapleader = " "
vim.g.maplocalleader = " "
-- }}} -------------------------------

-- -------------------- filetype {{{
-- https://zenn.dev/rapan931/articles/45b09b774512fc
local my_filetype = require("filetype")
vim.api.nvim_create_augroup("vimrc_augroup", {})
vim.api.nvim_create_autocmd("FileType", {
	group = "vimrc_augroup",
	pattern = "*",
	callback = function(args)
		my_filetype[args.match]()
	end,
})
-- }}} -------------------------------

-- -------------------- lazy.nvim {{{
-- https://github.com/folke/lazy.nvim
-- load lazy.nvim
-- see: https://github.com/euxn23/init-lua-and-lazy-nvim-sample
require("lazy_nvim")
-- }}} -------------------------------

-- -------------------- user command {{{
-- https://github.com/willelz/nvim-lua-guide-ja/blob/master/README.ja.md#%E3%83%A6%E3%83%BC%E3%82%B6%E3%83%BC%E3%82%B3%E3%83%9E%E3%83%B3%E3%83%89%E3%82%92%E5%AE%9A%E7%BE%A9%E3%81%99%E3%82%8B
function OpenGitURL(mode)
	local repo_name = vim.fn.systemlist(
		"git config --get remote.origin.url | grep -oP '(?<=git@|http://)(.*)(?=.git)' | sed 's/:/\\//'"
	)[1]
	--repo_nameにgithubの文字列が入るか判定
	local is_github = string.find(repo_name, "github")
	local is_gitlab = string.find(repo_name, "gitlab")
	local is_bitbucket = string.find(repo_name, "bitbucket")
	-- 明示的に対応したレポジトリ管理ツール以外はエラーを出力
	if is_github == nil and is_gitlab == nil and is_bitbucket == nil then
		print("This repository is neither github nor gitlab nor bitbucket")
		return
	end
	local filepath = GetFilePathFromRepoRoot()
	-- local branch = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")[1]
	local hash = vim.fn.systemlist("git rev-parse HEAD")[1]
	local start_line, end_line = GetCurrentLine(mode)
	local url = GenerateGitUrl(repo_name, hash, filepath, start_line, end_line, is_gitlab, is_bitbucket)
	print("Open: " .. url)
	-- wsl-open
	-- https://github.com/4U6U57/wsl-open/tree/master
	vim.fn.jobstart("wsl-open " .. url)
end

-- レポジトリrootからの相対パスを取得
function GetFilePathFromRepoRoot()
	local filename = vim.fn.expand("%")
	local filepath_from_root = vim.fn.systemlist("git ls-files --full-name " .. filename)[1]
	return filepath_from_root
end

-- normalモードの場合はカーソル位置の行数を取得
-- visualモードの場合は選択範囲の行数を取得
function GetCurrentLine(mode)
	local start_line = 0
	local end_line = 0
	if mode == "n" then
		-- normalモードの場合はカーソル位置の行数を取得
		start_line = vim.fn.line(".")
		end_line = vim.fn.line(".")
	elseif mode == "v" then
		start_line = vim.fn.getpos("'<")[2]
		end_line = vim.fn.getpos("'>")[2]
	else
		-- do nothing
	end
	return start_line, end_line
end

function GenerateGitUrl(repo_name, hash, filepath_from_root, start_line, end_line, is_gitlab, is_bitbucket)
	-- gitlabの場合はhttp、fdevがhttps対応してないため
	local url = (is_gitlab and "http://" or "https://")
		.. repo_name
		.. (is_bitbucket and "/src/" or "/blob/")
		.. hash
		.. "/"
		.. filepath_from_root
		.. (is_bitbucket and "#lines-" or "#L")
		.. start_line
		-- NOTE: gitlabとgithubで範囲選択の仕方が違うので注意
		-- is_gitlabは - のみ
		-- is_githubは -L となる
		.. (
			-- gitlabのときは -, githubのときは -L, bitbucketのときは :
			is_bitbucket and ":" or (is_gitlab and "-" or "-L")
		)
		.. end_line
	return url
end

vim.api.nvim_create_user_command("OpenGit", OpenGitURL, { nargs = 0 })
vim.api.nvim_set_keymap("n", "<leader>og", ":lua OpenGitURL('n')<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<leader>og", ":lua OpenGitURL('v')<CR>", { noremap = true, silent = true })
-- }}} -------------------------------
