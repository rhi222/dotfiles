local M = {}

M.name = "CpToHost"
M.description = "Copy current file to host machine desktop"

function M.run()
	local current_file = vim.fn.expand("%:p")
	if current_file == "" then
		vim.notify("No file is currently open", vim.log.levels.ERROR)
		return
	end

	local output = vim.fn.system("powershell.exe '$env:USERNAME'")
	local username = output:gsub("%s+", "")

	if username == "" then
		vim.notify("Failed to get username. Output: " .. output, vim.log.levels.ERROR)
		return
	end

	local desktop_path = "/mnt/c/Users/" .. username .. "/Desktop/"
	local filename = vim.fn.fnamemodify(current_file, ":t")
	local dest_path = desktop_path .. filename

	local cmd = "cp '" .. current_file .. "' '" .. dest_path .. "'"
	local result = vim.fn.system(cmd)

	if vim.v.shell_error == 0 then
		vim.notify("Copied " .. filename .. " to host desktop", vim.log.levels.INFO)
	else
		vim.notify("Failed to copy file: " .. result, vim.log.levels.ERROR)
	end
end

vim.api.nvim_create_user_command("CpToHost", M.run, {
	desc = M.description,
})

return M
