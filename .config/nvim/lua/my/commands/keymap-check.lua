local km = require("my.plugins.keymaps")

-- :KeymapList - 全keymapをprefix別にグループ表示
vim.api.nvim_create_user_command("KeymapList", function()
	local lines = { "=== Keymap Registry ===" }
	local categories = { "finder", "lsp", "completion", "git", "editing", "tools", "commands" }
	for _, cat in ipairs(categories) do
		local entries = km[cat]
		if type(entries) == "table" then
			table.insert(lines, "")
			table.insert(lines, string.format("--- %s ---", cat))
			local sorted = {}
			for name, entry in pairs(entries) do
				if type(entry) == "table" and entry[1] then
					local modes = entry.mode or "n"
					if type(modes) == "table" then
						modes = table.concat(modes, ",")
					end
					table.insert(sorted, { name = name, lhs = entry[1], modes = modes, desc = entry.desc or "" })
				end
			end
			table.sort(sorted, function(a, b)
				return a.lhs < b.lhs
			end)
			for _, item in ipairs(sorted) do
				table.insert(lines, string.format("  %-25s %-12s [%s] %s", item.name, item.lhs, item.modes, item.desc))
			end
		end
	end
	vim.api.nvim_echo({ { table.concat(lines, "\n"), "Normal" } }, true, {})
end, {})

-- :KeymapCheck - 重複keymapを検出して表示
vim.api.nvim_create_user_command("KeymapCheck", function()
	local duplicates = km.find_duplicates()
	if vim.tbl_isempty(duplicates) then
		vim.api.nvim_echo({ { "No duplicate keymaps found.", "Normal" } }, true, {})
		return
	end
	local lines = { "=== Duplicate Keymaps ===" }
	local sorted_keys = vim.tbl_keys(duplicates)
	table.sort(sorted_keys)
	for _, id in ipairs(sorted_keys) do
		local names = duplicates[id]
		table.insert(lines, string.format("  %s: %s", id, table.concat(names, ", ")))
	end
	vim.api.nvim_echo({ { table.concat(lines, "\n"), "WarningMsg" } }, true, {})
end, {})
