local M = {}

M.name = "CpToHost"
M.description = "Copy current file to host machine desktop"

-- Get Desktop path (OneDrive/日本語対応)
local function get_desktop_path()
	local ps = [[
    $p = [Environment]::GetFolderPath('Desktop');
    Write-Output $p
  ]]
	local output = vim.fn.system({ "powershell.exe", "-NoProfile", "-Command", ps })
	if vim.v.shell_error ~= 0 or output == "" then
		return nil, "Failed to get Desktop path from PowerShell"
	end
	-- CRLF 除去
	output = output:gsub("\r", ""):gsub("\n", "")
	-- WSLパスへ変換
	local wslpath = vim.fn.system({ "wslpath", "-u", output })
	if vim.v.shell_error ~= 0 or wslpath == "" then
		return nil, "Failed to convert Windows path: " .. output
	end
	return wslpath:gsub("\n", ""), nil
end

function M.run()
	local current_file = vim.fn.expand("%:p")
	if current_file == "" then
		vim.notify("No file is currently open", vim.log.levels.ERROR)
		return
	end

	local desktop_path, err = get_desktop_path()
	if not desktop_path then
		vim.notify(err, vim.log.levels.ERROR)
		return
	end

	local filename = vim.fn.fnamemodify(current_file, ":t")
	local dest_path = desktop_path .. "/" .. filename

	local result = vim.fn.system({ "cp", current_file, dest_path })
	if vim.v.shell_error == 0 then
		vim.notify("Copied " .. filename .. " to host desktop (" .. desktop_path .. ")", vim.log.levels.INFO)
	else
		vim.notify("Failed to copy file: " .. result, vim.log.levels.ERROR)
	end
end

vim.api.nvim_create_user_command("CpToHost", M.run, {
	desc = M.description,
})

return M
