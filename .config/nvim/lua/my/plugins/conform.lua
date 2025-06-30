-- https://github.com/stevearc/conform.nvim
-- NOTE: 開いているバッファにどのFormatterが割り当てられているか確認するコマンド:ConformInfo

-- LSPベースのJavaScript/TypeScriptフォーマッター検出
local function get_js_formatter()
	local buf = vim.api.nvim_get_current_buf()
	local clients = vim.lsp.get_clients({ bufnr = buf })

	-- JS/TS関連のLSPクライアントを探す
	for _, client in ipairs(clients) do
		if
			client.name:match("typescript")
			or client.name:match("javascript")
			or client.name == "volar"
			or client.name == "ts_ls"
		then
			local root = client.config.root_dir
			if root then
				-- プロジェクトルートでbiome設定を確認
				if
					vim.fn.filereadable(root .. "/biome.json") == 1
					or vim.fn.filereadable(root .. "/biome.jsonc") == 1
				then
					return { "biome" }
				end
			end
		end
	end

	-- LSPクライアントがない場合やbiome設定がない場合はprettierを使用
	return { "prettier" }
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
		go = { "goimports", "gofmt" },
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
