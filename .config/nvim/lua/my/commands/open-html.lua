local M = {}

M.name = "OpenHtml"
M.description = "Open current HTML file in the Windows host browser (WSL)"

-- 拡張子が .html / .htm かどうか（大文字小文字は無視）
local function is_html(path)
	return path:lower():match("%.html?$") ~= nil
end

function M.run()
	local current_file = vim.fn.expand("%:p")
	if current_file == "" then
		vim.notify("No file is currently open", vim.log.levels.ERROR)
		return
	end

	if not is_html(current_file) then
		vim.notify("Not an HTML file: " .. vim.fn.fnamemodify(current_file, ":t"), vim.log.levels.ERROR)
		return
	end

	-- WSL 専用（wslview で Windows 既定ブラウザに渡す）
	if vim.fn.has("wsl") ~= 1 then
		vim.notify("OpenHtml is only supported on WSL", vim.log.levels.ERROR)
		return
	end

	-- wslview が WSL パス → UNC への変換と既定アプリ起動を担う
	vim.fn.jobstart({ "wslview", current_file }, { detach = true })
	vim.notify("Opening " .. vim.fn.fnamemodify(current_file, ":t") .. " in host browser", vim.log.levels.INFO)
end

vim.api.nvim_create_user_command("OpenHtml", M.run, { desc = M.description })

return M
