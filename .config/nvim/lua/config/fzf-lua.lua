-- https://github.com/ibhagwan/fzf-lua#usage
vim.keymap.set("n", "<c-g>",
  "<cmd>lua require('fzf-lua').grep()<CR>", { silent = true })
require("fzf-lua").setup({})
