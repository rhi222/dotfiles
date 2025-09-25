-- 念のため mason が未初期化なら初期化（依存解決の保険）
if not package.loaded["mason"] then
	pcall(function()
		require("mason").setup({})
	end)
end

local mlsp = require("mason-lspconfig")

local function get_capabilities()
	local capabilities = vim.lsp.protocol.make_client_capabilities()
	local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
	if ok then
		capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
	end
	capabilities.textDocument.foldingRange = { dynamicRegistration = false, lineFoldingOnly = true }
	return capabilities
end

local capabilities = get_capabilities()

local server_overrides = {
	lua_ls = {
		settings = {
			Lua = {
				completion = { callSnippet = "Replace" },
				diagnostics = { globals = { "vim" } },
				workspace = { checkThirdParty = false },
				telemetry = { enable = false },
			},
		},
	},
	yamlls = {
		settings = {
			yaml = {
				keyOrdering = false,
				validate = true,
			},
		},
	},
}


local has_new_lsp = vim.fn.has("nvim-0.11") == 1 and type(vim.lsp) == "table" and vim.lsp.config

local legacy_lspconfig = nil
if not has_new_lsp then
	local ok, mod = pcall(require, "lspconfig")
	if ok then
		legacy_lspconfig = mod
	end
end

local function setup(server, opts)
	local merged_opts = { capabilities = capabilities }
	if opts then
		merged_opts = vim.tbl_deep_extend("force", merged_opts, opts)
	end
	if has_new_lsp then
		vim.lsp.config(server, merged_opts)
		if type(vim.lsp.enable) == "function" then
			vim.lsp.enable(server)
		end
		return
	end
	if legacy_lspconfig and type(legacy_lspconfig[server]) == "table" and type(legacy_lspconfig[server].setup) == "function" then
		legacy_lspconfig[server].setup(merged_opts)
		return
	end
	vim.notify_once(
		string.format("mason-lspconfig: LSP server '%s' is unavailable in this Neovim setup", server),
		vim.log.levels.WARN
	)
end

local function configure_server(server)
	if server == "pylsp" then
		return
	end
	setup(server, server_overrides[server])
end

mlsp.setup({
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
		"ts_ls", -- tsserver の新名
		"yamlls",
	},
})

if type(mlsp.setup_handlers) == "function" then
	mlsp.setup_handlers({
		function(server)
			configure_server(server)
		end,
	})
else
	for _, server in ipairs(mlsp.get_installed_servers()) do
		configure_server(server)
	end
end
