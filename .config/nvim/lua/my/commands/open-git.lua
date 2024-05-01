-- Enum-like table for repository types
local RepositoryType = {
	GITHUB = "github",
	GITLAB = "gitlab",
	BITBUCKET = "bitbucket",
}

-- Retrieves the URL of the Git repository from the remote origin configuration.
local function getRepositoryURL()
	local repo_url = vim.fn.systemlist(
		"git config --get remote.origin.url | grep -oP '(?<=git@|https://)(.*)(?=.git)' | sed 's/:/\\//'"
	)[1]
	if repo_url == "" then
		print("Unable to retrieve repository URL")
		return nil
	end
	return repo_url
end

-- Determines the type of repository based on the URL.
local function getRepositoryType(repo_url)
	if string.find(repo_url, "github") then
		return RepositoryType.GITHUB
	elseif string.find(repo_url, "gitlab") then
		return RepositoryType.GITLAB
	elseif string.find(repo_url, "bitbucket") then
		return RepositoryType.BITBUCKET
	else
		return nil
	end
end

-- Gets the file path from the repository root.
local function getFilePathFromRepoRoot()
	local filename = vim.fn.expand("%")
	local filepath = vim.fn.systemlist("git ls-files --full-name " .. filename)[1]
	if filepath == "" then
		print("Unable to find file in repository")
		return nil
	end
	return filepath
end

-- normalモードの場合はカーソル位置の行数を取得
-- visualモードの場合は選択範囲の行数を取得
local function getCurrentLineRange(mode)
	if mode == "n" then
		-- normalモードの場合はカーソル位置の行数を取得
		local line = vim.fn.line(".")
		return line, line
	elseif mode == "v" then
		return vim.fn.getpos("'<")[2], vim.fn.getpos("'>")[2]
	end
	return nil, nil
end

-- Generates a URL to the file in the Git hosting service.
local function generateGitUrl(repo_type, repo_url, hash, filepath, start_line, end_line)
	local base_url = (repo_type == RepositoryType.GITLAB and "http://" or "https://") .. repo_url
	local path = (repo_type == RepositoryType.BITBUCKET and "/src/" or "/blob/") .. hash .. "/" .. filepath
	local line_ref = (repo_type == RepositoryType.BITBUCKET and "#lines-" or "#L") .. start_line
	-- NOTE: repo_typeで範囲選択の仕方が違うので注意
	-- -- gitlabのときは -, githubのときは -L, bitbucketのときは :
	if start_line ~= end_line then
		line_ref = line_ref
			.. (repo_type == RepositoryType.GITLAB and "-" or (repo_type == RepositoryType.GITHUB and "-L" or ":"))
			.. end_line
	end
	return base_url .. path .. line_ref
end

-- Main function to handle the open URL command.
function OpenGitURL(mode)
	local repo_url = getRepositoryURL()
	if not repo_url then
		return
	end

	local repo_type = getRepositoryType(repo_url)
	-- 明示的に対応したレポジトリ管理ツール以外はエラーを出力
	if not repo_type then
		print("This repository is not supported. only github, gitlab, bitbucket are supported.")
		return
	end

	local filepath = getFilePathFromRepoRoot()
	if not filepath then
		return
	end

	local hash = vim.fn.systemlist("git rev-parse HEAD")[1]
	if hash == "" then
		print("Unable to retrieve Git hash")
		return
	end

	local start_line, end_line = getCurrentLineRange(mode)
	local url = generateGitUrl(repo_type, repo_url, hash, filepath, start_line, end_line)

	print("Opening URL: " .. url)
	-- wsl-open
	-- https://github.com/4U6U57/wsl-open/tree/master
	vim.fn.jobstart("wsl-open " .. url)
end

vim.api.nvim_create_user_command("OpenGit", OpenGitURL, { nargs = 0 })
vim.keymap.set("n", "<leader>og", ":lua OpenGitURL('n')<CR>", { noremap = true, silent = true })
vim.keymap.set("v", "<leader>og", ":lua OpenGitURL('v')<CR>", { noremap = true, silent = true })
