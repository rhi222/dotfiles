local augroup = vim.api.nvim_create_augroup("PlantumlPreview", { clear = true })

local function generate(file, png)
	vim.fn.system("plantuml -tpng " .. vim.fn.shellescape(file))
	if vim.v.shell_error ~= 0 then
		vim.notify("PlantUML: generation failed", vim.log.levels.ERROR)
		return false
	end
	return true
end

local function create_html(png, html)
	local img_name = vim.fn.fnamemodify(png, ":t")
	local content = string.format(
		[[<!DOCTYPE html>
<html><head><title>PlantUML Preview</title></head>
<body style="margin:0;display:flex;justify-content:center;align-items:center;min-height:100vh;background:#1e1e1e">
<img id="img" src="%s" style="max-width:100%%">
<script>setInterval(function(){var i=document.getElementById('img');i.src=i.src.split('?')[0]+'?t='+Date.now()},2000)</script>
</body></html>]],
		img_name
	)
	local f = io.open(html, "w")
	if f then
		f:write(content)
		f:close()
	end
end

vim.api.nvim_create_user_command("PlantumlPreview", function()
	local file = vim.fn.expand("%:p")
	local base = vim.fn.expand("%:p:r")
	local png = base .. ".png"
	local html = base .. "_preview.html"

	if not generate(file, png) then
		return
	end

	create_html(png, html)
	vim.fn.jobstart({ "wslview", html })

	-- 保存時に自動再生成（ブラウザが2秒ごとに画像を再読み込み）
	vim.api.nvim_clear_autocmds({ group = augroup })
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		buffer = 0,
		callback = function()
			generate(file, png)
		end,
	})

	vim.notify("PlantUML: preview started (auto-refresh on save)")
end, {})

vim.api.nvim_create_user_command("PlantumlStop", function()
	vim.api.nvim_clear_autocmds({ group = augroup })
	vim.notify("PlantUML: preview stopped")
end, {})
