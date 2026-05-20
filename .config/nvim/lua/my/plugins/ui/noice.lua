-- NOTE: nvim 0.12 で convert_input_to_markdown_lines / stylize_markdown が削除されたため
-- lsp.override は設定不要
require("noice").setup({
	presets = {
		bottom_search = true,
		command_palette = true,
		long_message_to_split = true,
		lsp_doc_border = false,
	},
})
