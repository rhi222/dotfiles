-- https://github.com/stevearc/conform.nvim
-- NOTE: 開いているバッファにどのFormatterが割り当てられているか確認するコマンド:ConformInfo

-- Conform will run multiple formatters sequentially, run the first available formatter
local formatter_js = { "biome", "prettier", stop_after_first = true }

-- 現在のファイルがあるGitリポジトリのルートを取得する関数
local function get_git_root()
	local git_dir = vim.fn.finddir(".git", ".;")
	if git_dir == "" then
		print("Error: .git directory not found")
		return nil -- `.git`ディレクトリが見つからない場合
	else
		return vim.fn.fnamemodify(git_dir, ":h")
	end
end

-- Gitリポジトリのルートに`biome.json`があるかを確認し、フォーマッタを設定
local function get_js_formatter()
	local root_dir = get_git_root()
	if root_dir then
		local biome_json_path = root_dir .. "/biome.json"
		local biome_jsonc_path = root_dir .. "/biome.jsonc"
		if vim.fn.filereadable(biome_json_path) == 1 or vim.fn.filereadable(biome_jsonc_path) == 1 then
			return { "biome" } -- `biome.json`がある場合は`biome`を使う
		else
			print("Warning: biome.json not found, using prettier")
			return { "prettier" } -- `biome.json`がない場合は`prettier`を使う
		end
	else
		print("Error: Git root not found, using prettier")
		return { "prettier" } -- Gitリポジトリのルートが見つからない場合も`prettier`を使う
	end
end

require("conform").setup({
	format_on_save = function(bufnr)
		-- Disable with a global or buffer-local variable
		if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
			return
		end
		return { timeout_ms = 5000, lsp_format = "fallback" }
	end,

	formatters_by_ft = {
		bash = { "shfmt" },
		fish = { "fish_indent" },
		html = { "prettier" },
		http = { "kulala" },
		javascript = get_js_formatter,
		javascriptreact = get_js_formatter,
		json = get_js_formatter,
		json5 = get_js_formatter,
		lua = { "stylua" },
		markdown = { "prettier" },
		python = function(bufnr)
			if require("conform").get_formatter_info("ruff_format", bufnr).available then
				return { "ruff_format" }
			else
				return { "isort", "black" }
			end
		end,
		rust = { "rustfmt", lsp_format = "fallback" },
		sql = { "sqlfluff", "injected" },
		typescript = get_js_formatter,
		typescriptreact = get_js_formatter,
		xml = { "xmlformat" },
		-- NOTE: yamlfmtを検討してもよいかも, なんならbiome?
		yaml = { "prettier" },
		-- Use the "_" filetype to run formatters on filetypes that don't
		-- have other formatters configured.
		["_"] = { "trim_whitespace" },
	},
	formatters = {
		kulala = {
			command = "kulala-fmt",
			args = { "format", "$FILENAME" },
			stdin = false,
		},
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

-- Command to toggle format-on-save
-- https://github.com/stevearc/conform.nvim/blob/master/doc/recipes.md#command-to-toggle-format-on-save
vim.api.nvim_create_user_command("FormatDisable", function(args)
	if args.bang then
		-- FormatDisable! will disable formatting just for this buffer
		vim.b.disable_autoformat = true
	else
		vim.g.disable_autoformat = true
	end
end, {
	desc = "Disable autoformat-on-save",
	bang = true,
})
vim.api.nvim_create_user_command("FormatEnable", function()
	vim.b.disable_autoformat = false
	vim.g.disable_autoformat = false
end, {
	desc = "Re-enable autoformat-on-save",
})
