-- Copy the current file path to the clipboard
local function copy_current_file_path(opts)
	local path = vim.fn.expand("%")
	if path == "" then
		vim.notify("No file path available", vim.log.levels.WARN)
		return
	end

	-- Get repository root path
	local final_path = path
	local full_path = vim.fn.expand("%:p")
	local git_dir = vim.fs.find(".git", { upward = true, path = vim.fs.dirname(full_path) })[1]
	if git_dir then
		local git_root = vim.fs.dirname(git_dir)
		final_path = full_path:sub(#git_root + 2) -- +2 for trailing "/"
	end

	-- Add line numbers if in visual mode
	if opts.range > 0 then
		if opts.line1 == opts.line2 then
			final_path = final_path .. ":" .. opts.line1
		else
			final_path = final_path .. ":" .. opts.line1 .. "-" .. opts.line2
		end
	end

	vim.fn.setreg("+", final_path)
	vim.notify("Copied to clipboard: " .. final_path, vim.log.levels.INFO)
end

vim.api.nvim_create_user_command(
	"CpCurrentFilePath",
	copy_current_file_path,
	{ desc = "Copy the current file path to the clipboard", range = true }
)

-- Copy the full (absolute) file path to the clipboard
local function copy_full_file_path(opts)
	local path = vim.fn.expand("%:p")
	if path == "" then
		vim.notify("No file path available", vim.log.levels.WARN)
		return
	end

	-- Add line numbers if in visual mode
	if opts.range > 0 then
		if opts.line1 == opts.line2 then
			path = path .. ":" .. opts.line1
		else
			path = path .. ":" .. opts.line1 .. "-" .. opts.line2
		end
	end

	vim.fn.setreg("+", path)
	vim.notify("Copied to clipboard: " .. path, vim.log.levels.INFO)
end

vim.api.nvim_create_user_command(
	"CpFullFilePath",
	copy_full_file_path,
	{ desc = "Copy the full file path to the clipboard", range = true }
)
