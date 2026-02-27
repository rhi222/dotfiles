if not package.loaded["mason"] then
	pcall(function()
		require("mason").setup({})
	end)
end

require("mason-lspconfig").setup({
	ensure_installed = {
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
	},
	-- automatic_enable (default: true) が全インストール済みサーバーに対して
	-- vim.lsp.config() + vim.lsp.enable() を自動実行する。
	-- サーバー固有設定は ~/.config/nvim/lsp/*.lua で定義。
})
