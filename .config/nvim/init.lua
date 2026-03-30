-- require nvim v0.9.0 or later
vim.loader.enable()

require("my/settings/option")

-- -------------------- filetype {{{
-- 参考:
-- https://github.com/skanehira/dotfiles/blob/master/vim/lua/my/settings/autocmd.lua
-- https://zenn.dev/rapan931/articles/45b09b774512fc
require("my/settings/autocmd")
-- }}} -------------------------------

-- -------------------- lazy.nvim {{{
-- https://github.com/folke/lazy.nvim
-- load lazy.nvim
-- see: https://github.com/euxn23/init-lua-and-lazy-nvim-sample
require("lazy_nvim")
-- }}} -------------------------------

-- -------------------- user command {{{
require("my/commands")
-- }}} -------------------------------

-- -------------------- builtin keymaps (nvim 0.12+) {{{
local km = require("my.plugins.keymaps")
local lhs, mode, desc = km.get("builtin", "undotree")
vim.keymap.set(mode, lhs, vim.cmd.Undotree, { desc = desc })
-- }}} -------------------------------
