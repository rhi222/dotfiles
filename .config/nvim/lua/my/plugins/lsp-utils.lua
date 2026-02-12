local M = {}

function M.get_capabilities()
	local capabilities = vim.lsp.protocol.make_client_capabilities()
	local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
	if ok then
		capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
	end
	capabilities.textDocument.foldingRange = { dynamicRegistration = false, lineFoldingOnly = true }
	return capabilities
end

M.has_new_lsp = vim.fn.has("nvim-0.11") == 1 and type(vim.lsp) == "table" and vim.lsp.config

M.legacy_lspconfig = nil
if not M.has_new_lsp then
	local ok, mod = pcall(require, "lspconfig")
	if ok then
		M.legacy_lspconfig = mod
	end
end

function M.setup_server(server, opts)
	if M.has_new_lsp then
		local overrides = opts and vim.tbl_deep_extend("force", {}, opts) or nil
		if overrides then
			vim.lsp.config(server, overrides)
		end
		if type(vim.lsp.enable) == "function" then
			vim.lsp.enable(server)
		end
		return true
	end
	if M.legacy_lspconfig and type(M.legacy_lspconfig[server]) == "table" and type(M.legacy_lspconfig[server].setup) == "function" then
		M.legacy_lspconfig[server].setup(opts or {})
		return true
	end
	vim.notify_once(
		string.format("LSP server '%s' is unavailable in this Neovim setup", server),
		vim.log.levels.WARN
	)
	return false
end

return M
