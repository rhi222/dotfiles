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
	local repo_root = vim.fn.systemlist("git rev-parse --show-toplevel 2> /dev/null")[1]
	if repo_root == "" then
		print("Unable to find repository root")
		return nil
	end
	local fullpath = vim.fn.expand("%:p")
	-- repo_root + "/" の長さを取って切り出し
	local prefix = repo_root:gsub("/+$", "") .. "/"
	if not fullpath:find(prefix, 1, true) then
		print("Unable to find file in repository")
		return nil
	end
	return fullpath:sub(#prefix + 1)
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
function OpenGitURL(mode)
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
vim.api.nvim_create_user_command("OpenGit", function()
	OpenGitURL("n")
end, {})
vim.keymap.set("n", "<leader>og", ":OpenGit<CR>", { noremap = true, silent = true })
vim.keymap.set("v", "<leader>og", ":lua OpenGitURL('v')<CR>", { noremap = true, silent = true })
