local diagnostic = vim.diagnostic
vim.keymap.set("n", "<space>e", diagnostic.open_float, { desc = "Open diagnostic float" })
vim.keymap.set("n", "[d", diagnostic.goto_prev, { desc = "Previous diagnostic" })
vim.keymap.set("n", "]d", diagnostic.goto_next, { desc = "Next diagnostic" })
vim.keymap.set("n", "<space>q", diagnostic.setloclist, { desc = "Diagnostics to location list" })

-- LSP attachment時にバッファローカルのキー設定を行う関数

-- Diagnosticの表示方法を変更
-- https://dev.classmethod.jp/articles/eetann-change-neovim-lsp-diagnostics-format/
local function format_virtual_text(entry)
	local segments = { entry.message }
	if entry.source then
		table.insert(segments, string.format("%s", entry.source))
	end
	if entry.code then
		table.insert(segments, string.format("%s", entry.code))
	end
	if #segments == 1 then
		return segments[1]
	end
	return string.format("%s (%s)", segments[1], table.concat(segments, ": ", 2))
end

diagnostic.config({
	float = { border = "rounded" },
	severity_sort = true,
	signs = true,
	update_in_insert = false,
	virtual_text = { format = format_virtual_text },
})

local lsp_utils = require("my.plugins.lsp.utils")

local default_capabilities = lsp_utils.get_capabilities()

local servers_without_formatting = { ts_ls = true }

local setup_server = lsp_utils.setup_server

local function enable_inlay_hints(buf)
	local ih = vim.lsp.inlay_hint
	if type(ih) ~= "table" then
		return
	end
	if type(ih.enable) ~= "function" then
		return
	end
	local ok = pcall(ih.enable, buf, true)
	if not ok then
		pcall(ih.enable, true, { bufnr = buf })
	end
end

local on_lsp_attach = function(ev)
	local buf = ev.buf
	local client = vim.lsp.get_client_by_id(ev.data.client_id)
	if not client then
		return
	end
	-- Enable omni-completion
	vim.bo[buf].omnifunc = "v:lua.vim.lsp.omnifunc"
	vim.bo[buf].formatexpr = "v:lua.vim.lsp.formatexpr()"

	-- 定義したマッピングをテーブルでまとめる
	local mappings = {
		{ mode = "n", key = "gD", func = vim.lsp.buf.declaration, desc = "LSP: Declaration" },
		{ mode = "n", key = "gd", func = vim.lsp.buf.definition, desc = "LSP: Definition" },
		{ mode = "n", key = "K", func = vim.lsp.buf.hover, desc = "LSP: Hover" },
		{ mode = "n", key = "gi", func = vim.lsp.buf.implementation, desc = "LSP: Implementation" },
		{ mode = "n", key = "<C-k>", func = vim.lsp.buf.signature_help, desc = "LSP: Signature Help" },
		{ mode = "n", key = "<space>wa", func = vim.lsp.buf.add_workspace_folder, desc = "LSP: Add workspace folder" },
		{
			mode = "n",
			key = "<space>wr",
			func = vim.lsp.buf.remove_workspace_folder,
			desc = "LSP: Remove workspace folder",
		},
		{
			mode = "n",
			key = "<space>wl",
			func = function()
				print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
			end,
			desc = "LSP: List workspace folders",
		},
		{ mode = "n", key = "<space>D", func = vim.lsp.buf.type_definition, desc = "LSP: Type definition" },
		{ mode = "n", key = "<space>rn", func = vim.lsp.buf.rename, desc = "LSP: Rename" },
		{ mode = { "n", "v" }, key = "<space>ca", func = vim.lsp.buf.code_action, desc = "LSP: Code action" },
		{ mode = "n", key = "gr", func = vim.lsp.buf.references, desc = "LSP: References" },
	}

	local opts = { buffer = buf }
	for _, map in ipairs(mappings) do
		local map_opts = vim.tbl_extend("force", opts, { desc = map.desc })
		vim.keymap.set(map.mode, map.key, map.func, map_opts)
	end

	if servers_without_formatting[client.name] then
		client.server_capabilities.documentFormattingProvider = false
		client.server_capabilities.documentRangeFormattingProvider = false
	end

	if client.supports_method("textDocument/documentHighlight") then
		local group = vim.api.nvim_create_augroup("UserLspDocumentHighlight" .. buf, { clear = true })
		vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
			group = group,
			buffer = buf,
			callback = vim.lsp.buf.document_highlight,
		})
		vim.api.nvim_create_autocmd("CursorMoved", {
			group = group,
			buffer = buf,
			callback = vim.lsp.buf.clear_references,
		})
	end

	if client.supports_method("textDocument/inlayHint") then
		enable_inlay_hints(buf)
	end
end

-- Use LspAttach autocommand to only map the following keys
-- after the language server attaches to the current buffer
-- LspAttachイベント時に上記関数を呼び出す
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = on_lsp_attach,
})

-- pylsp は自動有効化から除外したので、ここで個別設定
setup_server("pylsp", {
	capabilities = default_capabilities,
	settings = {
		pylsp = {
			plugins = {
				pycodestyle = {
					maxLineLength = 150,
					ignore = { "E402" }, -- module level import not at top of file
				},
				ruff = { enabled = false }, -- use dedicated ruff_lsp server when available
			},
		},
	},
})

-- 他サーバを上書きしたい場合の雛形（必要なときだけ追記）
-- vim.lsp.config.ts_ls.setup({
--   on_attach = function(client, bufnr) ... end,
--   capabilities = capabilities,
-- })
