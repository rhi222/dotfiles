-- https://github.com/ibhagwan/fzf-lua#usage
-- https://github.com/ibhagwan/fzf-lua/blob/main/doc/fzf-lua.txt
require("fzf-lua").setup({
	grep = {
		rg_opts = "--hidden --glob '!.git' --column --line-number --no-heading --color=always --smart-case --max-columns=4096 -e",
	},
})
vim.keymap.set("n", "<c-g>", "<cmd>lua require('fzf-lua').grep()<CR>", { silent = true })
-- note: telescope.builtin.find_files() is not working
vim.keymap.set("n", "<c-p>", "<cmd>lua require('fzf-lua').files()<CR>", { silent = true })
