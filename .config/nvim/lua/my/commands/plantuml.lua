-- PlantUML Viewer: サイドバー付き単一エンドポイントビューア
-- PlantumlOpen したファイルだけをビューアに登録 → SVG変換 → python3 http.serverで配信
-- http://localhost:3100 でサイドバー付きビューアを表示

local augroup = vim.api.nvim_create_augroup("PlantumlViewer", { clear = true })

local output_dir = nil
local server_job_id = nil
local debounce_timer = nil
local registered_files = {} -- { [absolute_path] = true }
local DEBOUNCE_MS = 1000
local SERVER_PORT = 3100

local function jar_path()
	local custom = vim.g["plantuml_previewer#plantuml_jar_path"]
	if custom then
		return custom
	end
	local base = vim.g["plantuml_previewer#viewer_path"]
	if base then
		return vim.fn.fnameescape(base) .. "/../lib/plantuml.jar"
	end
	local ok, path = pcall(function()
		return vim.fn["plantuml_previewer#default_viewer_path"]() .. "/../lib/plantuml.jar"
	end)
	if ok then
		return path
	end
	return nil
end

local function get_project_root()
	return vim.fn.getcwd()
end

local function relative_path(abs_path)
	local root = get_project_root()
	if vim.startswith(abs_path, root) then
		return abs_path:sub(#root + 2)
	end
	return vim.fn.fnamemodify(abs_path, ":.")
end

local function svg_name(puml_path)
	return relative_path(puml_path):gsub("/", "--"):gsub("%.puml$", ".svg")
end

local function write_manifest()
	if not output_dir then
		return
	end
	local entries = {}
	for abs_path, _ in pairs(registered_files) do
		local rel = relative_path(abs_path)
		table.insert(entries, string.format('    {"name": %q, "svg": %q}', rel, svg_name(abs_path)))
	end
	table.sort(entries)
	local json = string.format(
		'{\n  "files": [\n%s\n  ],\n  "updated_at": %d\n}',
		table.concat(entries, ",\n"),
		os.time()
	)
	local fh = io.open(output_dir .. "/manifest.json", "w")
	if fh then
		fh:write(json)
		fh:close()
	end
end

--- SVG変換を実行する
---@param puml_path string 変換対象の.pumlファイルの絶対パス
---@param on_complete? fun(success: boolean) 変換完了時のコールバック
local function convert_file(puml_path, on_complete)
	if not output_dir then
		return
	end
	local jar = jar_path()
	if not jar then
		vim.notify("PlantUML: plantuml.jar が見つかりません", vim.log.levels.ERROR)
		if on_complete then
			on_complete(false)
		end
		return
	end

	local src_dir = vim.fn.fnamemodify(puml_path, ":h")
	local svg = output_dir .. "/" .. svg_name(puml_path)

	-- バッファが開いていればバッファの内容を使う（未保存の変更を反映）
	local content
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == puml_path then
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			content = table.concat(lines, "\n")
			break
		end
	end

	local cmd = string.format(
		"java -Djava.awt.headless=true -DPLANTUML_LIMIT_SIZE=32768 -Dplantuml.include.path=%s -jar %s -tsvg -pipe > %s",
		vim.fn.shellescape(src_dir),
		vim.fn.shellescape(jar),
		vim.fn.shellescape(svg)
	)

	local job_opts = {}
	if on_complete then
		job_opts.on_exit = function(_, exit_code, _)
			vim.schedule(function()
				on_complete(exit_code == 0)
			end)
		end
	end

	if content then
		job_opts.stdin = "pipe"
		local job_id = vim.fn.jobstart({ "bash", "-c", cmd }, job_opts)
		if job_id > 0 then
			vim.fn.chansend(job_id, content)
			vim.fn.chanclose(job_id, "stdin")
		end
	else
		local read_cmd = string.format("cat %s | %s", vim.fn.shellescape(puml_path), cmd)
		vim.fn.jobstart({ "bash", "-c", read_cmd }, job_opts)
	end
end

local function notify_convert_error(puml_path)
	vim.notify(
		"PlantUML: " .. vim.fn.fnamemodify(puml_path, ":t") .. " の変換に失敗しました",
		vim.log.levels.WARN
	)
end

local function register_and_convert(abs_path)
	if not output_dir then
		return
	end
	registered_files[abs_path] = true
	write_manifest() -- サイドバーに即座に表示
	convert_file(abs_path, function(success)
		if success then
			write_manifest() -- SVG完了後にタイムスタンプ更新 → ブラウザが最新SVGを取得
		else
			notify_convert_error(abs_path)
		end
	end)
end

-- Neovim側でもmanifest.jsonを監視して registered_files を同期
local function sync_registered_files_from_manifest()
	if not output_dir then
		return
	end
	local manifest_path = output_dir .. "/manifest.json"
	local fh = io.open(manifest_path, "r")
	if not fh then
		return
	end
	local manifest_content = fh:read("*a")
	fh:close()

	-- manifest.jsonに残っているファイルだけを registered_files に反映
	local new_registered = {}
	for name in manifest_content:gmatch('"name"%s*:%s*"([^"]+)"') do
		local root = get_project_root()
		local abs_path = root .. "/" .. name
		if registered_files[abs_path] then
			new_registered[abs_path] = true
		end
	end
	registered_files = new_registered
end

-- サイドバー付きHTMLビューア / python3 http.server スクリプトは
-- lua/my/commands/plantuml/resources/ に外出ししている
local RESOURCE_DIR = "lua/my/commands/plantuml/resources"

local function read_resource(name)
	local files = vim.api.nvim_get_runtime_file(RESOURCE_DIR .. "/" .. name, false)
	if #files == 0 then
		vim.notify("PlantUML: resource not found: " .. name, vim.log.levels.ERROR)
		return nil
	end
	local fh = io.open(files[1], "r")
	if not fh then
		vim.notify("PlantUML: cannot open resource: " .. files[1], vim.log.levels.ERROR)
		return nil
	end
	local content = fh:read("*a")
	fh:close()
	return content
end

local function write_resource(name, dest)
	local content = read_resource(name)
	if not content then
		return false
	end
	local fh = io.open(dest, "w")
	if not fh then
		return false
	end
	fh:write(content)
	fh:close()
	return true
end

local function write_index_html()
	if not output_dir then
		return
	end
	write_resource("viewer.html", output_dir .. "/index.html")
end

local function write_server_py()
	if not output_dir then
		return
	end
	write_resource("server.py", output_dir .. "/server.py")
end

local function start_server()
	if server_job_id or not output_dir then
		return
	end
	write_server_py()
	server_job_id = vim.fn.jobstart({
		"python3", output_dir .. "/server.py",
		tostring(SERVER_PORT), output_dir,
	}, {
		on_stderr = function(_, data, _)
			vim.schedule(function()
				if data then
					local msg = vim.trim(table.concat(data, "\n"))
					if msg ~= "" then
						vim.notify("PlantUML server: " .. msg, vim.log.levels.WARN)
					end
				end
			end)
		end,
		on_exit = function(_, exit_code, _)
			vim.schedule(function()
				server_job_id = nil
				if exit_code ~= 0 then
					vim.notify(
						string.format("PlantUML: サーバーが異常終了しました (exit %d)", exit_code),
						vim.log.levels.ERROR
					)
				end
			end)
		end,
	})
end

local function stop_server()
	if server_job_id then
		vim.fn.jobstop(server_job_id)
		server_job_id = nil
	end
end

local function cleanup()
	stop_server()
	vim.api.nvim_clear_autocmds({ group = augroup })
	if debounce_timer then
		debounce_timer:stop()
		debounce_timer = nil
	end
	if output_dir then
		vim.fn.delete(output_dir, "rf")
		output_dir = nil
	end
	registered_files = {}
end

local function convert_and_update_manifest(puml_path)
	if not registered_files[puml_path] then
		return
	end
	convert_file(puml_path, function(success)
		if success then
			write_manifest()
		else
			notify_convert_error(puml_path)
		end
	end)
end

local function debounced_convert(puml_path)
	if debounce_timer then
		debounce_timer:stop()
	end
	debounce_timer = vim.defer_fn(function()
		debounce_timer = nil
		convert_and_update_manifest(puml_path)
	end, DEBOUNCE_MS)
end

-- manifest.json のポーリングタイマー（GUI側の削除をNeovim側に同期）
local manifest_poll_timer = nil
local function start_manifest_poll()
	if manifest_poll_timer then
		return
	end
	manifest_poll_timer = vim.uv.new_timer()
	manifest_poll_timer:start(3000, 3000, vim.schedule_wrap(function()
		sync_registered_files_from_manifest()
	end))
end

local function stop_manifest_poll()
	if manifest_poll_timer then
		manifest_poll_timer:stop()
		manifest_poll_timer:close()
		manifest_poll_timer = nil
	end
end

local function ensure_server_and_autocmds()
	if not server_job_id then
		-- 出力ディレクトリ作成
		output_dir = vim.fn.tempname() .. "_plantuml_viewer"
		vim.fn.mkdir(output_dir, "p")
		write_index_html()
		start_server()
		start_manifest_poll()

		-- ブラウザ起動（WSL環境ではwslviewを使用）
		vim.defer_fn(function()
			local open_cmd = vim.fn.has("wsl") == 1 and "wslview" or "xdg-open"
			vim.fn.jobstart({ open_cmd, "http://localhost:" .. SERVER_PORT }, { detach = true })
		end, 1000)

		-- 保存時に該当ファイルを再変換（登録済みのみ）
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = augroup,
			pattern = "*.puml",
			callback = function(args)
				local path = vim.api.nvim_buf_get_name(args.buf)
				if registered_files[path] then
					if debounce_timer then
						debounce_timer:stop()
						debounce_timer = nil
					end
					convert_and_update_manifest(path)
				end
			end,
		})

		-- テキスト変更時はデバウンスで再変換（登録済みのみ）
		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			group = augroup,
			pattern = "*.puml",
			callback = function(args)
				local path = vim.api.nvim_buf_get_name(args.buf)
				if path ~= "" and registered_files[path] then
					debounced_convert(path)
				end
			end,
		})

		-- VimLeave時にクリーンアップ
		vim.api.nvim_create_autocmd("VimLeave", {
			group = augroup,
			callback = function()
				stop_manifest_poll()
				cleanup()
			end,
		})
	end
end

local function plantuml_open_handler()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)

	if path == "" or not path:match("%.puml$") then
		vim.notify("PlantUML: 現在のバッファは .puml ファイルではありません", vim.log.levels.ERROR)
		return
	end

	if vim.fn.executable("java") == 0 then
		vim.notify("PlantUML: java が見つかりません", vim.log.levels.ERROR)
		return
	end
	if vim.fn.executable("python3") == 0 then
		vim.notify("PlantUML: python3 が見つかりません", vim.log.levels.ERROR)
		return
	end

	-- サーバーとautocmdを初期化（初回のみ）
	ensure_server_and_autocmds()

	-- 現在のファイルをビューアに登録・変換
	register_and_convert(path)

	local count = 0
	for _ in pairs(registered_files) do
		count = count + 1
	end

	if server_job_id and count > 1 then
		vim.notify(string.format("PlantUML: added %s (%d files total)", vim.fn.fnamemodify(path, ":t"), count))
	else
		vim.notify(string.format("PlantUML: viewer started at http://localhost:%d", SERVER_PORT))
	end
end

local function plantuml_stop_handler()
	if not server_job_id then
		vim.notify("PlantUML: viewer is not running")
		return
	end
	stop_manifest_poll()
	cleanup()
	vim.notify("PlantUML: viewer stopped")
end

-- コマンドを(再)定義する関数
-- plantuml-previewer.vimプラグインがPlantumlOpenを上書きするため、
-- プラグインロード後にconfig経由で再定義する必要がある
local function create_commands()
	vim.api.nvim_create_user_command("PlantumlOpen", plantuml_open_handler, { force = true })
	vim.api.nvim_create_user_command("PlantumlStop", plantuml_stop_handler, { force = true })
end

create_commands()

-- plantumlファイルでのみキーマップを設定
-- cleanup()でクリアされるPlantumlViewerとは別のaugroupを使用
local keymap_augroup = vim.api.nvim_create_augroup("PlantumlKeymaps", { clear = true })
local keymaps = require("my/plugins/keymaps")
local lhs, mode, desc = keymaps.get("commands", "plantuml_open")
vim.api.nvim_create_autocmd("FileType", {
	group = keymap_augroup,
	pattern = "plantuml",
	callback = function(args)
		vim.keymap.set(mode, lhs, "<cmd>PlantumlOpen<cr>", { buffer = args.buf, desc = desc })
	end,
})

return { create_commands = create_commands }
