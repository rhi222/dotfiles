-- No .setup() call is needed! Just set your options via vim.g.rest_nvi
vim.g.rest_nvim = {

    -- https://github.com/rest-nvim/rest.nvim?tab=readme-ov-file#default-configuration
}
vim.keymap.set("n", "<C-e>", "<cmd>Rest run<CR>", { desc = "Run rest command" })
