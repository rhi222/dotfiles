-- :MemoryCheck - Lua VMメモリ・バッファ数・LSPクライアント数・autocmd数を表示
vim.api.nvim_create_user_command("MemoryCheck", function()
	local lua_mem = collectgarbage("count")
	local bufs = vim.tbl_filter(function(b)
		return vim.api.nvim_buf_is_loaded(b)
	end, vim.api.nvim_list_bufs())
	local clients = vim.lsp.get_clients()
	local autocmds = vim.api.nvim_get_autocmds({})

	local lines = {
		"=== Memory Check ===",
		string.format("  Lua VM memory:    %.1f KB", lua_mem),
		string.format("  Loaded buffers:   %d", #bufs),
		string.format("  LSP clients:      %d", #clients),
		string.format("  Autocmds:         %d", #autocmds),
	}

	if #clients > 0 then
		table.insert(lines, "  LSP clients detail:")
		for _, c in ipairs(clients) do
			local attached = vim.tbl_count(c.attached_buffers or {})
			table.insert(lines, string.format("    - %s (id=%d, bufs=%d)", c.name, c.id, attached))
		end
	end

	vim.api.nvim_echo({ { table.concat(lines, "\n"), "Normal" } }, true, {})
end, { desc = "Show Neovim memory and resource usage" })

-- :MemoryClean - 手動GCを実行しメモリを解放
vim.api.nvim_create_user_command("MemoryClean", function()
	local before = collectgarbage("count")
	collectgarbage("collect")
	collectgarbage("collect")
	local after = collectgarbage("count")

	vim.notify(
		string.format("GC complete: %.1f KB -> %.1f KB (freed %.1f KB)", before, after, before - after),
		vim.log.levels.INFO
	)
end, { desc = "Run Lua garbage collection" })
