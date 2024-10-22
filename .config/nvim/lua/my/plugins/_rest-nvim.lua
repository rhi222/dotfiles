-- No .setup() call is needed! Just set your options via vim.g.rest_nvi
---@type rest.Opts
vim.g.rest_nvim = {
	-- https://github.com/rest-nvim/rest.nvim?tab=readme-ov-file#default-configuration
	request = {
		-- 予約記録のdev環境など検証系のエラー回避
		skip_ssl_verification = true,
	},
}
