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
	automatic_enable = true,
})

