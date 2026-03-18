-- plantuml-previewer.vim のバグ回避ラッパー
-- 1. bufnr('%') が誤ったバッファを返す問題 → Lua側でbufnr捕捉
-- 2. @startuml Name により出力ファイル名が変わる問題 → -pipe で直接出力
-- 3. 複数ファイル同時プレビュー対応 → バッファごとに独立したviewerディレクトリを使用

local augroup = vim.api.nvim_create_augroup("PlantumlPreviewerFix", { clear = true })

-- バッファごとのviewer情報を保持
local buf_viewers = {}
-- バッファごとのデバウンスタイマー
local buf_timers = {}
local DEBOUNCE_MS = 1000

local function base_viewer_path()
	local custom = vim.g["plantuml_previewer#viewer_path"]
	if custom then
		return vim.fn.fnameescape(custom)
	end
	return vim.fn["plantuml_previewer#default_viewer_path"]()
end

local function jar_path()
	local custom = vim.g["plantuml_previewer#plantuml_jar_path"]
	return custom or (base_viewer_path() .. "/../lib/plantuml.jar")
end

local function get_viewer_dir(bufnr)
	if buf_viewers[bufnr] then
		return buf_viewers[bufnr]
	end
	local tmpdir = vim.fn.tempname() .. "_plantuml_" .. bufnr
	vim.fn.mkdir(tmpdir, "p")
	-- ベースviewerからファイルをコピー
	local base = base_viewer_path()
	if vim.fn.isdirectory(base) == 0 then
		vim.fn["plantuml_previewer#copy_viewer_directory"]()
	end
	vim.fn.system({ "cp", "-r", base .. "/.", tmpdir })
	buf_viewers[bufnr] = tmpdir
	return tmpdir
end

local function refresh(bufnr)
	local vp = get_viewer_dir(bufnr)
	local src = vim.api.nvim_buf_get_name(bufnr)
	local src_dir = vim.fn.fnamemodify(src, ":h")
	local svg = vp .. "/tmp.svg"
	local js = vp .. "/tmp.js"
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	local cmd = string.format(
		"java -Djava.awt.headless=true -Dplantuml.include.path=%s -jar %s -tsvg -pipe > %s && echo 'window.updateDiagramURL(\"%s\")' > %s",
		vim.fn.shellescape(src_dir),
		vim.fn.shellescape(jar_path()),
		vim.fn.shellescape(svg),
		os.time(),
		vim.fn.shellescape(js)
	)
	local job_id = vim.fn.jobstart({ "bash", "-c", cmd }, {
		stdin = "pipe",
	})
	if job_id > 0 then
		vim.fn.chansend(job_id, content)
		vim.fn.chanclose(job_id, "stdin")
	end
end

local function refresh_debounced(bufnr)
	if buf_timers[bufnr] then
		buf_timers[bufnr]:stop()
	end
	buf_timers[bufnr] = vim.defer_fn(function()
		buf_timers[bufnr] = nil
		if vim.api.nvim_buf_is_valid(bufnr) then
			refresh(bufnr)
		end
	end, DEBOUNCE_MS)
end

vim.api.nvim_create_user_command("PlantumlOpen", function()
	local bufnr = vim.api.nvim_get_current_buf()

	if vim.fn.executable("java") == 0 then
		vim.notify("PlantUML: java が見つかりません", vim.log.levels.ERROR)
		return
	end
	local vp = get_viewer_dir(bufnr)

	vim.fn.delete(vp .. "/tmp.puml")
	vim.fn.delete(vp .. "/tmp.svg")

	refresh(bufnr)
	-- WSL2ではブラウザ起動(wslview等)が同期的に~1.6秒ブロックするため非同期化
	vim.fn.jobstart({ "xdg-open", vp .. "/index.html" }, { detach = true })

	-- 保存時は即座にレンダリング
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		buffer = bufnr,
		callback = function()
			if buf_timers[bufnr] then
				buf_timers[bufnr]:stop()
				buf_timers[bufnr] = nil
			end
			refresh(bufnr)
		end,
	})

	-- テキスト変更時はデバウンスしてレンダリング
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = augroup,
		buffer = bufnr,
		callback = function()
			refresh_debounced(bufnr)
		end,
	})

	local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
	vim.notify("PlantUML: preview started for " .. filename .. " (auto-refresh)")
end, { force = true })

vim.api.nvim_create_user_command("PlantumlStop", function()
	local bufnr = vim.api.nvim_get_current_buf()
	vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
	-- 一時ディレクトリを削除
	if buf_viewers[bufnr] then
		vim.fn.delete(buf_viewers[bufnr], "rf")
		buf_viewers[bufnr] = nil
	end
	vim.notify("PlantUML: preview stopped")
end, { force = true })

-- バッファ削除時に一時ディレクトリをクリーンアップ
vim.api.nvim_create_autocmd("BufDelete", {
	group = augroup,
	callback = function(args)
		if buf_viewers[args.buf] then
			vim.fn.delete(buf_viewers[args.buf], "rf")
			buf_viewers[args.buf] = nil
		end
	end,
})
