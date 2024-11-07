-- https://github.com/stevearc/conform.nvim
-- NOTE: 開いているバッファにどのFormatterが割り当てられているか確認するコマンド:ConformInfo

-- Conform will run multiple formatters sequentially, run the first available formatter
local formatter_js = { "biome", "prettier", stop_after_first = true }

-- 現在のファイルがあるGitリポジトリのルートを取得する関数
local function get_git_root()
	local git_dir = vim.fn.finddir(".git", vim.fn.fnamemodify(vim.fn.expand("%:p:h"), ":h") .. ";")
	if git_dir == "" then
		return nil -- `.git`ディレクトリが見つからない場合
	else
		return vim.fn.fnamemodify(git_dir, ":h")
	end
end

-- Gitリポジトリのルートに`biome.json`があるかを確認し、フォーマッタを設定
local function get_js_formatter()
	local root_dir = get_git_root()
	if root_dir and vim.fn.filereadable(root_dir .. "/biome.json") == 1 then
		return { "biome" } -- `biome.json`がある場合は`biome`を使う
	else
		return { "prettier" } -- `biome.json`がない場合は`prettier`を使う
	end
end

require("conform").setup({
	format_on_save = {
		timeout_ms = 5000,
		lsp_format = "fallback",
	},
	formatters_by_ft = {
		bash = { "shfmt" },
		html = { "prettier" },
		javascript = get_js_formatter,
		javascriptreact = get_js_formatter,
		json = { "prettier" },
		json5 = { "prettier" },
		lua = { "stylua" },
		markdown = { "prettier" },
		python = { "ruff", "black", stop_after_first = true },
		rust = { "rustfmt", lsp_format = "fallback" },
		sql = { "sqlfluff", "injected" },
		typescript = get_js_formatter,
		typescriptreact = get_js_formatter,
		xml = { "xmlformat" },
		-- Use the "_" filetype to run formatters on filetypes that don't
		-- have other formatters configured.
		["_"] = { "trim_whitespace" },
	},
	formatters = {
		sqlfluff = {
			-- note: configファイル指定
			command = "sqlfluff",
			args = { "format", "--dialect", "postgres", "-" },
			stdin = true,
			condition = function()
				return true
			end,
		},
	},
})

-- https://github.com/stevearc/conform.nvim/blob/master/doc/recipes.md#format-command
vim.api.nvim_create_user_command("Format", function(args)
	local range = nil
	if args.count ~= -1 then
		local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
		range = {
			start = { args.line1, 0 },
			["end"] = { args.line2, end_line:len() },
		}
	end
	require("conform").format({ async = true, lsp_format = "fallback", range = range })
end, { range = true })
