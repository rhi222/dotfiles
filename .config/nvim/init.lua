-- require nvim v0.9.0 or later
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
require("my/command")
-- }}} -------------------------------
