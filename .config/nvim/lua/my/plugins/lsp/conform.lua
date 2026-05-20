-- https://github.com/stevearc/conform.nvim
-- NOTE: 開いているバッファにどのFormatterが割り当てられているか確認するコマンド: :ConformInfo

--------------------------------------------------------------------------------
-- 低コスト・堅牢なフォーマッタ検出（モノレポ対応 & キャッシュ付き）
--------------------------------------------------------------------------------
local uv = vim.uv or vim.loop

-- ディレクトリ単位の探索結果キャッシュ
-- key: dir(絶対パス), value: "biome" | "prettier" | "none"
local DIR_CACHE = {}

-- package.json の decode 結果キャッシュ
-- key: /abs/path/package.json, value: decoded table or false
local PKG_CACHE = {}

-- バッファ単位の最終判定キャッシュ
-- （vim.b.js_formatter は buffer-local なので別定義不要だが、nil と区別のため用意）
local function clear_buffer_formatter_cache(bufnr)
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		vim.b[bufnr].js_formatter = nil
	else
		vim.b.js_formatter = nil
	end
end

local function fs_readable(p)
	local st = uv.fs_stat(p)
	return st and st.type == "file"
end

local function fs_isdir(p)
	local st = uv.fs_stat(p)
	return st and st.type == "directory"
end

local function read_json_once(pkg)
	if PKG_CACHE[pkg] ~= nil then
		return PKG_CACHE[pkg]
	end
	if not fs_readable(pkg) then
		PKG_CACHE[pkg] = false
		return false
	end
	local ok, decoded = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(pkg), "\n"))
	end)
	PKG_CACHE[pkg] = (ok and type(decoded) == "table") and decoded or false
	return PKG_CACHE[pkg]
end

-- Prettier 設定ファイルの存在判定（package.json の "prettier" は呼び出し側で見る）
-- https://prettier.io/docs/configuration
local PRETTIER_CONF_FILES = {
	".prettierrc",
	".prettierrc.json",
	".prettierrc.json5",
	".prettierrc.yaml",
	".prettierrc.yml",
	".prettierrc.toml",
	".prettierrc.js",
	".prettierrc.cjs",
	".prettierrc.mjs",
	".prettierrc.ts",
	".prettierrc.cts",
	".prettierrc.mts",
	"prettier.config.js",
	"prettier.config.cjs",
	"prettier.config.mjs",
	"prettier.config.ts",
	"prettier.config.cts",
	"prettier.config.mts",
}

local function has_prettier_conf_file(dir)
	for _, n in ipairs(PRETTIER_CONF_FILES) do
		if fs_readable(dir .. "/" .. n) then
			return true
		end
	end
	return false
end

-- 探索開始ディレクトリのサニタイズ：
-- node_modules, .git, dist/build 等にいる時は一段上へ（パッケージ境界に寄せる）
local BANNED_LEAF_DIRS = {
	["node_modules"] = true,
	[".git"] = true,
	["dist"] = true,
	["build"] = true,
	["out"] = true,
}

local function sanitize_start_dir(dir)
	if dir == "" or not dir then
		return dir
	end
	local leaf = vim.fs.basename(dir)
	if BANNED_LEAF_DIRS[leaf] then
		local parent = vim.fs.dirname(dir)
		if parent ~= "" and parent ~= dir then
			return parent
		end
	end
	return dir
end

-- あるディレクトリから上方向に探索して、どのフォーマッタを使うかを決める
-- ルール（近い順優先・各階層で formatter 検出を全部行ってから境界判定）:
--  1. 同階層に biome.json / biome.jsonc または package.json の "biome" → "biome"
--  2. 同階層に Prettier 設定ファイル または package.json の "prettier" → "prettier"
--  3. 上記いずれも無い場合のみ、package.json の "workspaces" / .git で境界打ち切り
--     （monorepo root に .prettierrc がある構成で先に "none" になるのを防ぐため）
--  見つからなければ "none"
local function decide_for_dir(start_dir)
	start_dir = sanitize_start_dir(start_dir)
	if not start_dir or start_dir == "" then
		return "none"
	end

	-- 既にこのディレクトリで判定済みなら即返す
	if DIR_CACHE[start_dir] then
		return DIR_CACHE[start_dir]
	end

	local seen = {} -- 今回の探索で辿ったディレクトリ（バルクでキャッシュ埋める用）

	local function cache_and_return(decision)
		for _, d in ipairs(seen) do
			DIR_CACHE[d] = decision
		end
		return decision
	end

	local dir = start_dir
	local MAX_UP = 15

	for _ = 1, MAX_UP do
		seen[#seen + 1] = dir

		local pkg = read_json_once(dir .. "/package.json")

		-- 1) biome 検出（同階層の biome.json / biome.jsonc / package.json#biome）
		local has_biome = fs_readable(dir .. "/biome.json") or fs_readable(dir .. "/biome.jsonc")
		if pkg and pkg.biome ~= nil then
			has_biome = true
		end
		if has_biome then
			return cache_and_return("biome")
		end

		-- 2) prettier 検出（同階層の Prettier 設定ファイル / package.json#prettier）
		local has_prettier = has_prettier_conf_file(dir)
		if pkg and pkg.prettier ~= nil then
			has_prettier = true
		end
		if has_prettier then
			return cache_and_return("prettier")
		end

		-- 3) ここまで何も無ければ境界判定（workspaces / .git）
		if pkg and pkg.workspaces ~= nil then
			return cache_and_return("none")
		end
		if fs_isdir(dir .. "/.git") then
			return cache_and_return("none")
		end

		local parent = vim.fs.dirname(dir)
		if parent == "" or parent == dir then
			break
		end
		dir = parent
	end

	return cache_and_return("none")
end

-- バッファごとの最終判定（キャッシュ付き）
local function get_js_formatter_cached()
	local buf = vim.api.nvim_get_current_buf()

	-- 既に決定済みなら即返す
	if vim.b.js_formatter then
		return { vim.b.js_formatter }
	end

	local fname = vim.api.nvim_buf_get_name(buf)
	if fname == "" then
		-- 未保存バッファは安全側で Prettier
		vim.b.js_formatter = "prettier"
		return { "prettier" }
	end

	local start_dir = vim.fs.dirname(fname)
	local decision = decide_for_dir(start_dir)

	if decision == "biome" then
		vim.b.js_formatter = "biome"
		return { "biome" }
	elseif decision == "prettier" then
		vim.b.js_formatter = "prettier"
		return { "prettier" }
	else
		vim.b.js_formatter = "prettier"
		return { "prettier" }
	end
end

--------------------------------------------------------------------------------
-- 起動後プリウォーム（よく使うルートを非同期で温める）
--------------------------------------------------------------------------------
local function prewarm_decision_async()
	-- カレントワーキングディレクトリと、直近のバッファのディレクトリを温める
	local dirs = {}
	local cwd = vim.fn.getcwd()
	if cwd and cwd ~= "" then
		dirs[#dirs + 1] = cwd
	end
	local bufs = vim.api.nvim_list_bufs()
	for _, b in ipairs(bufs) do
		if vim.api.nvim_buf_is_loaded(b) then
			local name = vim.api.nvim_buf_get_name(b)
			if name ~= "" then
				local d = vim.fs.dirname(name)
				if d and d ~= "" then
					dirs[#dirs + 1] = d
				end
			end
		end
	end

	-- 重複排除
	local uniq = {}
	local seen = {}
	for _, d in ipairs(dirs) do
		if not seen[d] then
			uniq[#uniq + 1] = d
			seen[d] = true
		end
	end

	-- 非同期で少しずつ実行（UIブロックを回避）
	local i = 1
	local function step()
		if i > #uniq then
			return
		end
		local d = uniq[i]
		decide_for_dir(d) -- キャッシュされるだけで副作用なし
		i = i + 1
		vim.defer_fn(step, 5) -- 5ms 間隔で小刻みに
	end
	step()
end

-- 起動後 200ms でプリウォーム
vim.defer_fn(prewarm_decision_async, 200)

--------------------------------------------------------------------------------
-- Conform.nvim 設定（元ファイルをベースに最小変更：検出関数を差し替え）
--------------------------------------------------------------------------------
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
		javascript = get_js_formatter_cached, -- ★差し替え
		javascriptreact = get_js_formatter_cached, -- ★差し替え
		json = get_js_formatter_cached, -- ★差し替え
		json5 = get_js_formatter_cached, -- ★差し替え
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
		typescript = get_js_formatter_cached, -- ★差し替え
		typescriptreact = get_js_formatter_cached, -- ★差し替え
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

--------------------------------------------------------------------------------
-- :Format コマンド（範囲対応・元ファイル踏襲）
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Format on save のトグル（元ファイル踏襲）
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- キャッシュ無効化フック（ディレクトリ移動・設定変更時）
--------------------------------------------------------------------------------
-- 全バッファの formatter キャッシュをクリア
-- 設定ファイル変更時に、既に開いている他バッファが古い判定を持ち続けるのを防ぐ
local function clear_all_formatter_caches()
	DIR_CACHE = {}
	PKG_CACHE = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		clear_buffer_formatter_cache(bufnr)
	end
end

vim.api.nvim_create_autocmd({ "DirChanged" }, {
	callback = clear_all_formatter_caches,
})

vim.api.nvim_create_autocmd({ "BufWritePost" }, {
	pattern = vim.list_extend({
		"package.json",
		"biome.json",
		"biome.jsonc",
	}, PRETTIER_CONF_FILES),
	callback = clear_all_formatter_caches,
})
