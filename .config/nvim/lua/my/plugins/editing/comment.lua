require("Comment").setup({
	-- keymapの備忘のため、defaultの設定を明記
	---LHS of operator-pending mappings in NORMAL and VISUAL mode
	opleader = {
		---Line-comment keymap
		line = "gc",
		---Block-comment keymap
		block = "gb",
	},
})
