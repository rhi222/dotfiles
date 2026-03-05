-- plantuml-previewer.vim のバグ回避ラッパー
-- 1. bufnr('%') が誤ったバッファを返す問題 → Lua側でbufnr捕捉
-- 2. @startuml Name により出力ファイル名が変わる問題 → -pipe で直接出力

local augroup = vim.api.nvim_create_augroup("PlantumlPreviewerFix", { clear = true })

local function viewer_path()
	local custom = vim.g["plantuml_previewer#viewer_path"]
	if custom then
		return vim.fn.fnameescape(custom)
	end
	return vim.fn["plantuml_previewer#default_viewer_path"]()
end

local function jar_path()
	local custom = vim.g["plantuml_previewer#plantuml_jar_path"]
	return custom or (viewer_path() .. "/../lib/plantuml.jar")
end

local function refresh(bufnr)
	local vp = viewer_path()
	local src = vim.api.nvim_buf_get_name(bufnr)
	local src_dir = vim.fn.fnamemodify(src, ":h")
	local svg = vp .. "/tmp.svg"
	local js = vp .. "/tmp.js"

	local cmd = string.format(
		"java -Djava.awt.headless=true -Dplantuml.include.path=%s -jar %s -tsvg -pipe < %s > %s && echo 'window.updateDiagramURL(\"%s\")' > %s",
		vim.fn.shellescape(src_dir),
		vim.fn.shellescape(jar_path()),
		vim.fn.shellescape(src),
		vim.fn.shellescape(svg),
		os.time(),
		vim.fn.shellescape(js)
	)
	vim.fn.jobstart({ "bash", "-c", cmd })
end

vim.api.nvim_create_user_command("PlantumlOpen", function()
	local bufnr = vim.api.nvim_get_current_buf()

	if vim.fn.executable("java") == 0 then
		vim.notify("PlantUML: java が見つかりません", vim.log.levels.ERROR)
		return
	end
	if vim.fn.exists("*OpenBrowser") == 0 then
		vim.notify("PlantUML: open-browser.vim が必要です", vim.log.levels.ERROR)
		return
	end

	local vp = viewer_path()
	if vim.fn.isdirectory(vp) == 0 and vim.fn.filereadable(vp) == 0 then
		vim.fn["plantuml_previewer#copy_viewer_directory"]()
	end

	vim.fn.delete(vp .. "/tmp.puml")
	vim.fn.delete(vp .. "/tmp.svg")

	refresh(bufnr)
	vim.fn.OpenBrowser(vp .. "/index.html")

	vim.api.nvim_clear_autocmds({ group = augroup })
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		buffer = bufnr,
		callback = function()
			refresh(bufnr)
		end,
	})

	vim.notify("PlantUML: preview started (auto-refresh on save)")
end, { force = true })

vim.api.nvim_create_user_command("PlantumlStop", function()
	vim.api.nvim_clear_autocmds({ group = augroup })
	vim.notify("PlantUML: preview stopped")
end, { force = true })
