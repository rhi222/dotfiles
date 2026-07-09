-- nvim-lspconfig の tailwindcss はroot判定に `.git` フォールバックを含むため（tailwind v4対応）、
-- tailwindを使わないgitリポジトリにもアタッチし、ワークスペース走査でメモリを浪費する。
-- tailwind/postcss の設定ファイル、または package.json の tailwind 依存が見つかった場合のみ
-- アタッチするよう root_dir を上書きする（on_dir を呼ばなければアタッチされない）。
-- after/lsp/ に置く理由: プラグインの lsp/*.lua より優先されるのは after/lsp/ のみ (:h lsp-config-merge)
---@type vim.lsp.Config
return {
	root_dir = function(bufnr, on_dir)
		local config_files = {
			"tailwind.config.js",
			"tailwind.config.cjs",
			"tailwind.config.mjs",
			"tailwind.config.ts",
			"postcss.config.js",
			"postcss.config.cjs",
			"postcss.config.mjs",
			"postcss.config.ts",
		}
		local fname = vim.api.nvim_buf_get_name(bufnr)
		local found = vim.fs.find(config_files, { path = fname, upward = true })[1]
		if found then
			on_dir(vim.fs.dirname(found))
			return
		end
		-- tailwind v4 は設定ファイル不要のため、package.json の依存宣言でも判定する
		for _, pkg in ipairs(vim.fs.find("package.json", { path = fname, upward = true, limit = math.huge })) do
			local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(pkg), "\n"))
			if ok and type(data) == "table" then
				local deps = vim.tbl_extend("force", data.dependencies or {}, data.devDependencies or {})
				if deps.tailwindcss or deps["@tailwindcss/postcss"] or deps["@tailwindcss/vite"] then
					on_dir(vim.fs.dirname(pkg))
					return
				end
			end
		end
	end,
}
