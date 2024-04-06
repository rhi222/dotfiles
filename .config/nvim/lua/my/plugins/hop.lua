-- https://github.com/phaazon/hop.nvim
require("hop").setup({
	keys = "asdghklqwertyuiopzxcvbnmfj",
	create_hl_autocmd = true,
})
vim.keymap.set("n", "<leader>j", ":HopWord<CR>", { noremap = true })
