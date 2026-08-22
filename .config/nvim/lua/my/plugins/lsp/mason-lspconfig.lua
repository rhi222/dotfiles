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
		"markdown_oxide",
		"prismals",
		"pylsp",
		"ruff",
		"sqlls",
		"tailwindcss",
		"ts_ls",
		"yamlls",
	},
	-- automatic_enable は全インストール済みserverが対象。ensure_installedから
	-- 外しただけでは既存のMarksmanも起動するため、移行元を明示的に除外する。
	automatic_enable = {
		exclude = { "marksman" },
	},
	-- サーバー固有設定は ~/.config/nvim/lsp/*.lua で定義。
})
