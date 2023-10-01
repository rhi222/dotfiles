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
-- 特殊文字表示
-- https://qiita.com/pollenjp/items/459a08a2cc59485fa08b
vim.opt.list = true
vim.opt.listchars = { tab = ">-", trail = "*", nbsp = "+" }
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

-- -------------------- LSP/補完 {{{
-- 参考: https://zenn.dev/fukakusa_kadoma/articles/99e8f3ab855a56
-- TODO: LSPAttach移行
-- https://zenn.dev/ryoppippi/articles/8aeedded34c914
-- TODO: 設定ファイル分割
local on_attach = function(_, bufnr)
	local set = vim.keymap.set
	local opts = { buffer = bufnr }
	-- https://github.com/neovim/nvim-lspconfig#suggested-configuration
	-- 今後整理するためによく使うもの順
	set("n", "<space>e", vim.diagnostic.open_float)
	set("n", "[d", vim.diagnostic.goto_prev)
	set("n", "]d", vim.diagnostic.goto_next)
	set("n", "gd", vim.lsp.buf.definition, opts)
	set("n", "K", vim.lsp.buf.hover, opts)
	set("n", "gr", vim.lsp.buf.references, opts)
	set("n", "<space>D", vim.lsp.buf.type_definition, opts)

	set("n", "<space>q", vim.diagnostic.setloclist)
	set("n", "gD", vim.lsp.buf.declaration, opts)
	set("n", "gi", vim.lsp.buf.implementation, opts)
	set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
	set("n", "<space>wa", vim.lsp.buf.add_workspace_folder, opts)
	set("n", "<space>wr", vim.lsp.buf.remove_workspace_folder, opts)
	set("n", "<space>wl", function()
		print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
	end, opts)
	set("n", "<space>rn", vim.lsp.buf.rename, opts)
	set({ "n", "v" }, "<space>ca", vim.lsp.buf.code_action, opts)
end

-- Diagnosticの表示方法を変更
-- https://dev.classmethod.jp/articles/eetann-change-neovim-lsp-diagnostics-format/
vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
	update_in_insert = false,
	virtual_text = {
		format = function(diagnostic)
			return string.format("%s (%s: %s)", diagnostic.message, diagnostic.source, diagnostic.code)
		end,
	},
})

-- 補完プラグインのcmp_nvim_lspとLSPを連携
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require("cmp_nvim_lsp").default_capabilities(capabilities)

require("mason").setup()
require("mason-lspconfig").setup({
	ensure_installed = {
		"graphql",
		"marksman",
		"lua_ls",
		"pylsp", -- 動かすためにvirtualenvが必要だった: https://qiita.com/hwatahik/items/788e26e8d61e42d4d837
		"sqlls",
		"tsserver",
		"jsonls",
		"prismals",
		-- "lemminx",
		"yamlls",
	},
})

Servers = {
	-- https://github.com/python-lsp/python-lsp-server/blob/develop/CONFIGURATION.md
	pylsp = {
		pylsp = {
			-- flake8に統一したいが若干ノイジー
			configurationSources = { "flake8" },
			plugins = {
				pycodestyle = {
					-- https://qiita.com/KuruwiC/items/8e12704e338e532eb34a
					ignore = {
						"W503", -- blackと競合する
						"E402", -- build.pyでsys.path.appendの後にimportするため
					},
					maxLineLength = 200,
				},
			},
		},
	},
}
-- FIXME: .config/pycodestyleの設定をinit.luaに寄せる
require("mason-lspconfig").setup_handlers({
	function(server_name) -- default handler (optional)
		require("lspconfig")[server_name].setup({
			on_attach = on_attach, --keyバインドなどの設定を登録
			capabilities = capabilities, --cmpを連携
			-- Serversに設定がなければ空
			settings = Servers[server_name] or {},
		})
	end,
})
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
	-- githubとgitlab以外はエラー
	if is_github == nil and is_gitlab == nil then
		print("This repository is not github or gitlab")
		return
	end
	local filepath = GetFilePathFromRepoRoot()
	-- local branch = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")[1]
	local hash = vim.fn.systemlist("git rev-parse HEAD")[1]
	local start_line, end_line = GetCurrentLine(mode)
	local url = GenerateGitUrl(repo_name, hash, filepath, start_line, end_line, is_gitlab)
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

function GenerateGitUrl(repo_name, hash, filepath_from_root, start_line, end_line, is_gitlab)
	-- gitlabの場合はhttp、fdevがhttps対応してないため
	local url = (is_gitlab and "http://" or "https://")
		.. repo_name
		.. "/blob/"
		.. hash
		.. "/"
		.. filepath_from_root
		.. "#L"
		.. start_line
		-- NOTE: gitlabとgithubで範囲選択の仕方が違うので注意
		-- is_gitlabは - のみ
		-- is_githubは -L となる
		.. (is_gitlab and "-" or "-L")
		.. end_line
	return url
end

vim.api.nvim_create_user_command("OpenGit", OpenGitURL, { nargs = 0 })
vim.api.nvim_set_keymap("n", "<leader>og", ":lua OpenGitURL('n')<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<leader>og", ":lua OpenGitURL('v')<CR>", { noremap = true, silent = true })
-- }}} -------------------------------
