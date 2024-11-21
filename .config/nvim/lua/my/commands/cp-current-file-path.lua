-- Copy the current file path to the clipboard
local function copy_current_file_path()
	local path = vim.fn.expand("%")
	if path == "" then
		vim.notify("No file path available", vim.log.levels.WARN)
		return
	end
	vim.fn.setreg("+", path)
	vim.notify("Copied to clipboard: " .. path, vim.log.levels.INFO)
end

vim.api.nvim_create_user_command(
	"CpCurrentFilePath",
	copy_current_file_path,
	{ desc = "Copy the current file path to the clipboard" }
)
