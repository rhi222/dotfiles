-- LSPと補完の設定をまとめて実施
-- mason -> mason-lspconfig -> lspconfigの順番で設定が必須
-- https://github.com/williamboman/mason-lspconfig.nvim#setup

-- 参考: https://zenn.dev/fukakusa_kadoma/articles/99e8f3ab855a56
-- https://zenn.dev/ryoppippi/articles/8aeedded34c914

-- https://github.com/williamboman/mason.nvim
local servers = {
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

-- 補完プラグインのcmp_nvim_lspとLSPを連携
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require("cmp_nvim_lsp").default_capabilities(capabilities)

local handlers = {
	function(server_name) -- default handler (optional)
		require("lspconfig")[server_name].setup({
			-- on_attach = on_attach, --keyバインドなどの設定を登録
			capabilities = capabilities, --cmpを連携
			-- Serversに設定がなければ空
			settings = servers[server_name] or {},
		})
	end,
}

require("mason").setup()
require("mason-lspconfig").setup({
	ensure_installed = {
		"biome",
		"graphql",
		"marksman",
		"lua_ls",
		"pylsp", -- 動かすためにvirtualenvが必要だった: https://qiita.com/hwatahik/items/788e26e8d61e42d4d837
		"sqlls",
		"tailwindcss",
		"tsserver",
		"jsonls",
		"prismals",
		-- "lemminx",
		"yamlls",
	},
	handlers = handlers,
})
