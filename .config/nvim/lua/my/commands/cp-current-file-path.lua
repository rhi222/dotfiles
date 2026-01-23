-- Copy the current file path to the clipboard
local function copy_current_file_path(opts)
	local path = vim.fn.expand("%")
	if path == "" then
		vim.notify("No file path available", vim.log.levels.WARN)
		return
	end

	-- Get repository root path
	local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
	local final_path = path

	if vim.v.shell_error == 0 and git_root ~= "" then
		-- We're in a git repository, get relative path from repo root
		local full_path = vim.fn.expand("%:p")
		local repo_relative_path = vim.fn.fnamemodify(full_path, ":s?" .. vim.fn.escape(git_root, "?\\") .. "/??")
		final_path = repo_relative_path
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
