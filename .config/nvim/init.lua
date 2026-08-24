-- require nvim v0.12.0 or later
-- 0.12 未満で動かない主なもの: vim.lsp.config と lsp/*.lua（0.11+）、
-- vim.lsp.codelens.enable と vim.lsp.document_color（0.12）、
-- nvim-treesitter の main ブランチ、noice.nvim の 0.12 対応fork
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

-- -------------------- global keymap (非プラグイン) {{{
require("my/settings/keymap")
-- }}} -------------------------------
