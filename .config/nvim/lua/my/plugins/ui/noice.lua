require("noice").setup({
	lsp = {
		-- convert_input_to_markdown_lines / stylize_markdown は nvim 0.12 で削除済みのため override 不要
		override = {},
	},
	presets = {
		bottom_search = true,
		command_palette = true,
		long_message_to_split = true,
		lsp_doc_border = false,
	},
})
