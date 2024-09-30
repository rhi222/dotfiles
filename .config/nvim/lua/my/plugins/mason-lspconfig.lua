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

require("mason-lspconfig").setup({
	ensure_installed = {
		"biome",
		"graphql",
		"jsonls",
		"lua_ls",
		"marksman",
		"prismals",
		"pylsp", -- 動かすためにvirtualenvが必要だった: https://qiita.com/hwatahik/items/788e26e8d61e42d4d837
		"ruff-lsp",
		"sqlls",
		"tailwindcss",
		"ts_ls",
		"yamlls",
	},
	handlers = handlers,
})

