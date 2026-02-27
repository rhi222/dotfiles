local km = require("my.plugins.keymaps")
local diagnostic = vim.diagnostic

local diag_float_lhs, diag_float_mode, diag_float_desc = km.get("lsp", "diagnostic_float")
vim.keymap.set(diag_float_mode, diag_float_lhs, diagnostic.open_float, { desc = diag_float_desc })
local diag_prev_lhs, diag_prev_mode, diag_prev_desc = km.get("lsp", "diagnostic_prev")
vim.keymap.set(diag_prev_mode, diag_prev_lhs, function()
	diagnostic.jump({ count = -1 })
end, { desc = diag_prev_desc })
local diag_next_lhs, diag_next_mode, diag_next_desc = km.get("lsp", "diagnostic_next")
vim.keymap.set(diag_next_mode, diag_next_lhs, function()
	diagnostic.jump({ count = 1 })
end, { desc = diag_next_desc })
local diag_loclist_lhs, diag_loclist_mode, diag_loclist_desc = km.get("lsp", "diagnostic_loclist")
vim.keymap.set(diag_loclist_mode, diag_loclist_lhs, diagnostic.setloclist, { desc = diag_loclist_desc })

-- Diagnosticの表示方法
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

-- グローバルcapabilities (全サーバーに適用)
local lsp_utils = require("my.plugins.lsp.utils")
vim.lsp.config("*", {
	capabilities = lsp_utils.get_capabilities(),
})

local servers_without_formatting = { ts_ls = true }

local function enable_inlay_hints(bufnr)
	vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
end

-- LSP keymapの定義テーブル
local lsp_keymap_defs = {
	{ name = "declaration", func = vim.lsp.buf.declaration },
	{ name = "definition", func = vim.lsp.buf.definition },
	{ name = "hover", func = vim.lsp.buf.hover },
	{ name = "implementation", func = vim.lsp.buf.implementation },
	{ name = "signature_help", func = vim.lsp.buf.signature_help },
	{ name = "workspace_add", func = vim.lsp.buf.add_workspace_folder },
	{ name = "workspace_remove", func = vim.lsp.buf.remove_workspace_folder },
	{
		name = "workspace_list",
		func = function()
			print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
		end,
	},
	{ name = "type_definition", func = vim.lsp.buf.type_definition },
	{ name = "rename", func = vim.lsp.buf.rename },
	{ name = "code_action", func = vim.lsp.buf.code_action },
	{ name = "references", func = vim.lsp.buf.references },
}

local on_lsp_attach = function(ev)
	local buf = ev.buf
	local client = vim.lsp.get_client_by_id(ev.data.client_id)
	if not client then
		return
	end
	vim.bo[buf].omnifunc = "v:lua.vim.lsp.omnifunc"
	vim.bo[buf].formatexpr = "v:lua.vim.lsp.formatexpr()"

	local opts = { buffer = buf }
	for _, map in ipairs(lsp_keymap_defs) do
		local lhs, mode, desc = km.get("lsp", map.name)
		local map_opts = vim.tbl_extend("force", opts, { desc = desc })
		vim.keymap.set(mode, lhs, map.func, map_opts)
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

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = on_lsp_attach,
})
