-- 補完プラグインのcmp_nvim_lspとLSPを連携
local capabilities = vim.lsp.protocol.make_client_capabilities()

local ensure_installed = {
	"biome",
	"graphql",
	"jsonls",
	"lua_ls",
	"marksman",
	"prismals",
	"pylsp",
	"ruff",
	"sqlls",
	"tailwindcss",
	"ts_ls",
	"yamlls",
}

require("mason-lspconfig").setup({
	ensure_installed = ensure_installed,
	automatic_enable = {
		exclude = { "pylsp" },
	},
})

-- pylspの個別設定
require("lspconfig").pylsp.setup({
	capabilities = capabilities,
	settings = {
		pylsp = {
			plugins = {
				pycodestyle = {
					maxLineLength = 150,
					ignore = {
						"E402", -- module level import not at top of file
					},
				},
			},
		},
	},
})
