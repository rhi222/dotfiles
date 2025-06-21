-- see: https://github.com/neovim/nvim-lspconfig#suggested-configuration
-- Global diagnostic key mappings
-- See `:help vim.diagnostic.*` for documentation on any of the below functions
local diagnostic = vim.diagnostic
vim.keymap.set("n", "<space>e", diagnostic.open_float, { desc = "Open diagnostic float" })
vim.keymap.set("n", "[d", diagnostic.goto_prev, { desc = "Previous diagnostic" })
vim.keymap.set("n", "]d", diagnostic.goto_next, { desc = "Next diagnostic" })
vim.keymap.set("n", "<space>q", diagnostic.setloclist, { desc = "Diagnostics to location list" })

-- LSP attachment時にバッファローカルのキー設定を行う関数
local on_lsp_attach = function(ev)
	local buf = ev.buf
	-- Enable omni-completion
	vim.bo[buf].omnifunc = "v:lua.vim.lsp.omnifunc"

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
		opts.desc = map.desc
		vim.keymap.set(map.mode, map.key, map.func, opts)
	end
end

-- Use LspAttach autocommand to only map the following keys
-- after the language server attaches to the current buffer
-- LspAttachイベント時に上記関数を呼び出す
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = on_lsp_attach,
})

-- Diagnosticの表示方法を変更
-- https://dev.classmethod.jp/articles/eetann-change-neovim-lsp-diagnostics-format/
vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.lsp.handlers["textDocument/publishDiagnostics"], {
	update_in_insert = false,
	virtual_text = {
		format = function(diagnostic)
			return string.format("%s (%s: %s)", diagnostic.message, diagnostic.source, diagnostic.code)
		end,
	},
})

-- 参考記事:
-- https://zenn.dev/fukakusa_kadoma/articles/99e8f3ab855a56
-- https://zenn.dev/ryoppippi/articles/8aeedded34c914
