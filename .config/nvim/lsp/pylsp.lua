---@type vim.lsp.Config
return {
	settings = {
		pylsp = {
			plugins = {
				pycodestyle = {
					maxLineLength = 150,
					ignore = { "E402" },
				},
				ruff = { enabled = false },
			},
		},
	},
}
