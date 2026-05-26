-- difit: GitHub-likeなdiffビューアをブラウザで起動
-- https://github.com/yoshiko-pg/difit

local function get_cwd()
	local bufname = vim.api.nvim_buf_get_name(0)
	-- 通常ファイル以外（terminal/help/oil等）はバッファ名がパスとして使えないため cwd にfallback
	if bufname ~= "" and vim.bo.buftype == "" then
		return vim.fn.fnamemodify(bufname, ":p:h")
	end
	return vim.fn.getcwd()
end

local function is_git_repo(cwd)
	vim.fn.system({ "git", "-C", cwd, "rev-parse", "--git-dir" })
	return vim.v.shell_error == 0
end

vim.api.nvim_create_user_command("Difit", function()
	if vim.fn.executable("difit") ~= 1 then
		vim.notify("Difit: difit コマンドが見つかりません", vim.log.levels.ERROR)
		return
	end

	local cwd = get_cwd()

	if not is_git_repo(cwd) then
		vim.notify("Difit: gitリポジトリではありません (" .. cwd .. ")", vim.log.levels.ERROR)
		return
	end

	local job = vim.fn.jobstart({ "difit", "." }, { cwd = cwd, detach = true })
	if job <= 0 then
		vim.notify("Difit: 起動に失敗しました (jobstart=" .. job .. ")", vim.log.levels.ERROR)
		return
	end
	print("Difit: 差分を開きます")
end, {})
