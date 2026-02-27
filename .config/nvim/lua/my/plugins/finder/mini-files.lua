require("mini.files").setup({
	content = {
		-- hidden ファイルを表示するフィルター
		filter = nil, -- デフォルトで隠しファイルも表示される
	},
	-- netrw を置き換え
	options = {
		use_as_default_explorer = true,
	},
	windows = {
		preview = true,
		width_preview = 40,
	},
})
