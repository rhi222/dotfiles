-- -------------------- general mapping {{{
vim.scriptencoding = "utf-8"
vim.o.number = true
vim.o.tabpagemax = 50
-- indent
vim.o.tabstop = 4
vim.o.softtabstop = 4
vim.o.shiftwidth = 4
-- search
vim.o.incsearch = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.hlsearch = true
-- https://qiita.com/shiena/items/3f51a2c0b4722427e430
vim.o.cursorline = true
vim.o.cursorcolumn = true
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
-- TODO: which つかって他環境でも動くようにしたい
vim.g.python_host_prog = "/usr/bin/python2"
vim.g.python3_host_prog = "/usr/bin/python3"
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

-- LSP, 補完
-- TODO: 取りあえず動くようにしたので要精査
-- https://zenn.dev/fukakusa_kadoma/articles/99e8f3ab855a56
local on_attach = function(_, _)
	-- LSPが持つフォーマット機能を無効化する
	-- →例えばtsserverはデフォルトでフォーマット機能を提供しますが、利用したくない場合はコメントアウトを解除してください
	--client.server_capabilities.documentFormattingProvider = false
	-- 下記ではデフォルトのキーバインドを設定しています
	-- ほかのLSPプラグインを使う場合（例：Lspsaga）は必要ないこともあります

	local set = vim.keymap.set
	set("n", "gd", "<cmd>lua vim.lsp.buf.definition()<CR>")
	set("n", "K", "<cmd>lua vim.lsp.buf.hover()<CR>")
	set("n", "<C-m>", "<cmd>lua vim.lsp.buf.signature_help()<CR>")
	set("n", "gy", "<cmd>lua vim.lsp.buf.type_definition()<CR>")
	set("n", "rn", "<cmd>lua vim.lsp.buf.rename()<CR>")
	set("n", "ma", "<cmd>lua vim.lsp.buf.code_action()<CR>")
	set("n", "gr", "<cmd>lua vim.lsp.buf.references()<CR>")
	set("n", "<space>e", "<cmd>lua vim.lsp.diagnostic.show_line_diagnostics()<CR>")
	set("n", "[d", "<cmd>lua vim.lsp.diagnostic.goto_prev()<CR>")
	set("n", "]d", "<cmd>lua vim.lsp.diagnostic.goto_next()<CR>")
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
require("mason-lspconfig").setup_handlers({
	function(server_name) -- default handler (optional)
		require("lspconfig")[server_name].setup({
			on_attach = on_attach, --keyバインドなどの設定を登録
			capabilities = capabilities, --cmpを連携
		})
	end,
})
