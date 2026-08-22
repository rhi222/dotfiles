---@type vim.lsp.Config
return {
	-- markdown-oxide uses dynamic file watching for newly created notes and
	-- unresolved-link completions. Keep blink.cmp's capabilities and enable the
	-- watcher explicitly as recommended by markdown-oxide.
	capabilities = vim.tbl_deep_extend("force", require("my.plugins.lsp.utils").get_capabilities(), {
		workspace = {
			didChangeWatchedFiles = {
				dynamicRegistration = true,
			},
		},
	}),
}
