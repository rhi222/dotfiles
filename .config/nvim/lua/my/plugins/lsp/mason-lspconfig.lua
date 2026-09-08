if not package.loaded["mason"] then
	pcall(function()
		require("mason").setup({})
	end)
end

local servers = {
	"bashls",
	"biome",
	"fish_lsp",
	"gopls",
	"graphql",
	"jsonls",
	"lua_ls",
	"markdown_oxide",
	"prismals",
	"ruff",
	"sqls",
	"taplo",
	"tailwindcss",
	"ts_ls",
	"ty",
	"yamlls",
}

require("mason-lspconfig").setup({
	ensure_installed = servers,
	automatic_enable = servers,
	-- サーバー固有設定は ~/.config/nvim/lsp/*.lua で定義。
})
