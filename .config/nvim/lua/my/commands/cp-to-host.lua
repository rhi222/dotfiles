local M = {}

M.name = "CpToHost"
M.description = "Copy current file to host machine desktop"

-- PowerShell で Desktop の実体パスを取得（UTF-8出力を強制）
local function get_desktop_path()
	local ps = [[
    $ErrorActionPreference = 'Stop';
    $p = [Environment]::GetFolderPath('Desktop');
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false);
    Write-Output $p
  ]]
	local win = vim.fn.system({ "powershell.exe", "-NoProfile", "-Command", ps })
	if vim.v.shell_error ~= 0 or win == nil or win == "" then
		return nil, "Failed to get Desktop path from PowerShell"
	end
	-- 改行・CR除去
	win = (win:gsub("\r", "")):gsub("\n", "")

	-- WSL パスへ変換
	local unix = vim.fn.system({ "wslpath", "-u", win })
	if vim.v.shell_error ~= 0 or unix == nil or unix == "" then
		return nil, "Failed to convert Windows path: " .. win
	end
	unix = (unix:gsub("\r", "")):gsub("\n", "")

	-- 実在確認。存在しなければ候補を順に当てる（OneDrive/英語/日本語）
	if vim.fn.isdirectory(unix) == 1 then
		return unix, nil
	end

	-- USERPROFILE を取り、候補を総当たり
	local prof = vim.fn.system({
		"powershell.exe",
		"-NoProfile",
		"-Command",
		"$ErrorActionPreference='Stop'; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); $env:USERPROFILE",
	})
	prof = (prof or ""):gsub("\r", ""):gsub("\n", "")
	if prof ~= "" then
		local candidates = {
			prof .. "\\OneDrive\\Desktop",
			prof .. "\\OneDrive\\デスクトップ",
			prof .. "\\Desktop",
		}
		for _, c in ipairs(candidates) do
			local u = vim.fn.system({ "wslpath", "-u", c })
			u = (u or ""):gsub("\r", ""):gsub("\n", "")
			if u ~= "" and vim.fn.isdirectory(u) == 1 then
				return u, nil
			end
		end
	end

	return nil, "Desktop path not found (tried: " .. unix .. ")"
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

	-- system(list) で安全に引数を渡す（スペース・日本語OK）
	local result = vim.fn.system({ "cp", current_file, dest_path })
	if vim.v.shell_error == 0 then
		vim.notify("Copied " .. filename .. " → " .. desktop_path, vim.log.levels.INFO)
	else
		vim.notify("Failed to copy file: " .. result, vim.log.levels.ERROR)
	end
end

vim.api.nvim_create_user_command("CpToHost", M.run, { desc = M.description })

return M
