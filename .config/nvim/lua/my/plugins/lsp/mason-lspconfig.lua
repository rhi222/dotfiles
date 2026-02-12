-- 念のため mason が未初期化なら初期化（依存解決の保険）
if not package.loaded["mason"] then
	pcall(function()
		require("mason").setup({})
	end)
end

local mlsp = require("mason-lspconfig")
local lsp_utils = require("my.plugins.lsp-utils")

local capabilities = lsp_utils.get_capabilities()

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


local function configure_server(server)
	if server == "pylsp" then
		return
	end
	local opts = { capabilities = capabilities }
	if server_overrides[server] then
		opts = vim.tbl_deep_extend("force", opts, server_overrides[server])
	end
	lsp_utils.setup_server(server, opts)
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
