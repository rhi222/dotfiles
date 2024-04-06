
-- -------------------- user command {{{
-- https://github.com/willelz/nvim-lua-guide-ja/blob/master/README.ja.md#%E3%83%A6%E3%83%BC%E3%82%B6%E3%83%BC%E3%82%B3%E3%83%9E%E3%83%B3%E3%83%89%E3%82%92%E5%AE%9A%E7%BE%A9%E3%81%99%E3%82%8B
function OpenGitURL(mode)
	local repo_name = vim.fn.systemlist(
		"git config --get remote.origin.url | grep -oP '(?<=git@|http://)(.*)(?=.git)' | sed 's/:/\\//'"
	)[1]
	--repo_nameにgithubの文字列が入るか判定
	local is_github = string.find(repo_name, "github")
	local is_gitlab = string.find(repo_name, "gitlab")
	local is_bitbucket = string.find(repo_name, "bitbucket")
	-- 明示的に対応したレポジトリ管理ツール以外はエラーを出力
	if is_github == nil and is_gitlab == nil and is_bitbucket == nil then
		print("This repository is neither github nor gitlab nor bitbucket")
		return
	end
	local filepath = GetFilePathFromRepoRoot()
	-- local branch = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")[1]
	local hash = vim.fn.systemlist("git rev-parse HEAD")[1]
	local start_line, end_line = GetCurrentLine(mode)
	local url = GenerateGitUrl(repo_name, hash, filepath, start_line, end_line, is_gitlab, is_bitbucket)
	print("Open: " .. url)
	-- wsl-open
	-- https://github.com/4U6U57/wsl-open/tree/master
	vim.fn.jobstart("wsl-open " .. url)
end

-- レポジトリrootからの相対パスを取得
function GetFilePathFromRepoRoot()
	local filename = vim.fn.expand("%")
	local filepath_from_root = vim.fn.systemlist("git ls-files --full-name " .. filename)[1]
	return filepath_from_root
end

-- normalモードの場合はカーソル位置の行数を取得
-- visualモードの場合は選択範囲の行数を取得
function GetCurrentLine(mode)
	local start_line = 0
	local end_line = 0
	if mode == "n" then
		-- normalモードの場合はカーソル位置の行数を取得
		start_line = vim.fn.line(".")
		end_line = vim.fn.line(".")
	elseif mode == "v" then
		start_line = vim.fn.getpos("'<")[2]
		end_line = vim.fn.getpos("'>")[2]
	else
		-- do nothing
	end
	return start_line, end_line
end

function GenerateGitUrl(repo_name, hash, filepath_from_root, start_line, end_line, is_gitlab, is_bitbucket)
	-- gitlabの場合はhttp、fdevがhttps対応してないため
	local url = (is_gitlab and "http://" or "https://")
		.. repo_name
		.. (is_bitbucket and "/src/" or "/blob/")
		.. hash
		.. "/"
		.. filepath_from_root
		.. (is_bitbucket and "#lines-" or "#L")
		.. start_line
		-- NOTE: gitlabとgithubで範囲選択の仕方が違うので注意
		-- is_gitlabは - のみ
		-- is_githubは -L となる
		.. (
			-- gitlabのときは -, githubのときは -L, bitbucketのときは :
			is_bitbucket and ":" or (is_gitlab and "-" or "-L")
		)
		.. end_line
	return url
end

vim.api.nvim_create_user_command("OpenGit", OpenGitURL, { nargs = 0 })
vim.api.nvim_set_keymap("n", "<leader>og", ":lua OpenGitURL('n')<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<leader>og", ":lua OpenGitURL('v')<CR>", { noremap = true, silent = true })
-- }}} -------------------------------
