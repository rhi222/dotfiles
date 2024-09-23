-- https://github.com/ibhagwan/fzf-lua#usage
-- https://github.com/ibhagwan/fzf-lua/blob/main/doc/fzf-lua.txt
require("fzf-lua").setup({
	grep = {
		rg_opts = "--hidden --glob '!.git' --column --line-number --no-heading --color=always --smart-case --max-columns=4096 -e",
	},
})
