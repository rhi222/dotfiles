-- init.lua
local neogit = require("neogit")
neogit.setup({})
vim.keymap.set("n", "<leader>g", "<cmd>lua require('neogit').open()<CR>", { noremap = true })
