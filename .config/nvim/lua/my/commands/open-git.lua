-- Enum-like table for repository types
local RepositoryType = {
	GITHUB = "github",
	GITLAB = "gitlab",
	BITBUCKET = "bitbucket",
}

-- 1) リモート URL のパースを Lua 文字列操作に置き換え
local function getRepositoryURL()
	-- 1) リモート URL を取得
	local raw = vim.fn.system("git remote get-url origin 2> /dev/null"):gsub("%s+", "")
	if raw == "" then
		print("Unable to retrieve repository URL")
		return nil
	end

	-- 2) SSH のパターンを HTTPS 風に正規化
	--    git@github.com:owner/repo.git      → github.com/owner/repo
	--    ssh://git@github.com/owner/repo.git → github.com/owner/repo
	--    https://github.com/owner/repo.git   → github.com/owner/repo
	local host_path = raw
		-- strip protocol prefixes
		:gsub("^git@", "")
		:gsub("^ssh://git@", "")
		:gsub("^ssh://", "")
		:gsub("^https?://", "")
		-- strip .git suffix
		:gsub("%.git$", "")
		-- convert ":" (SSH のパス区切り) を "/"
		:gsub(":", "/")

	return host_path
end

-- 2) ファイルパスの取得を Lua だけで完結

local function getFilePathFromRepoRoot()
	local fullpath = vim.fn.expand("%:p")
	local git_dir = vim.fs.find(".git", { upward = true, path = vim.fn.expand("%:p:h") })[1]
	if not git_dir then
		print("Unable to find repository root")
		return nil
	end
	local repo_root = vim.fs.dirname(git_dir)
	return fullpath:sub(#repo_root + 2) -- +2 for trailing "/"
end

-- normal/visual で行範囲を取る部分はそのまま
local function getCurrentLineRange(mode)
	if mode == "n" then
		local line = vim.fn.line(".")
		return line, line
	elseif mode == "v" then
		return vim.fn.getpos("'<")[2], vim.fn.getpos("'>")[2]
	end
	return nil, nil
end

-- URL エンコード（スラッシュは除外）

local function urlencode(str)
	if not str then
		return ""
	end
	str = str:gsub("\n", "\r\n")
	return (str:gsub("([^%w%-%.%_%~%/])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

-- URL 組み立て
local function generateGitUrl(repo_type, repo_url, hash, filepath, start_line, end_line)
	-- gitlab.fdev ドメインの場合は HTTP、それ以外は HTTPS
	local protocol = repo_url:match("gitlab%.fdev") and "http://" or "https://"
	local base = protocol .. repo_url

	-- ブラブ部はそのまま
	local blob = (repo_type == RepositoryType.BITBUCKET) and "/src/" or "/blob/"

	local path = blob .. hash .. "/" .. filepath

	local line_ref = (repo_type == RepositoryType.BITBUCKET and "#lines-" or "#L") .. start_line
	if start_line ~= end_line then
		local sep = (repo_type == RepositoryType.GITLAB and "-" or (repo_type == RepositoryType.GITHUB and "-L" or ":"))
		line_ref = line_ref .. sep .. end_line
	end

	return base .. urlencode(path) .. line_ref
end

-- Main
local function OpenGitURL(mode)
	local repo_url = getRepositoryURL()
	if not repo_url then
		return
	end

	local repo_type = nil

	if repo_url:match("github") then
		repo_type = RepositoryType.GITHUB
	elseif repo_url:match("gitlab") then
		repo_type = RepositoryType.GITLAB
	elseif repo_url:match("bitbucket") then
		repo_type = RepositoryType.BITBUCKET
	end
	if not repo_type then
		print("Unsupported repository (only GitHub/GitLab/Bitbucket)")
		return
	end

	local filepath = getFilePathFromRepoRoot()

	if not filepath then
		return
	end

	local hash = vim.fn.systemlist("git rev-parse HEAD 2> /dev/null")[1]
	if hash == "" then
		print("Unable to retrieve Git hash")
		return
	end

	local s, e = getCurrentLineRange(mode)
	local url = generateGitUrl(repo_type, repo_url, hash, filepath, s, e)

	print("Opening URL: " .. url)
	-- 3) jobstart を引数テーブルで呼び出し
	vim.fn.jobstart({ "wsl-open", url }, { detach = true })
end

-- コマンド／マッピング登録
local km = require("my.plugins.keymaps")
vim.api.nvim_create_user_command("OpenGit", function()
	OpenGitURL("n")
end, {})
local og_lhs, _, og_desc = km.get("commands", "open_git")
vim.keymap.set("n", og_lhs, ":OpenGit<CR>", { noremap = true, silent = true, desc = og_desc })
local ogv_lhs, ogv_mode, ogv_desc = km.get("commands", "open_git_visual")
vim.keymap.set(ogv_mode, ogv_lhs, function()
	OpenGitURL("v")
end, { noremap = true, silent = true, desc = ogv_desc })
