-- https://github.com/nvim-telescope/telescope.nvim#usage
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<C-p>', builtin.find_files, {})
-- vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
-- vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
-- vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
--
-- https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/103
local actions = require "telescope.actions"
local fb_actions = require "telescope".extensions.file_browser.actions
require("telescope").setup {
  extensions = {
    file_browser = {
      -- theme = "ivy",
      -- disables netrw and use telescope-file-browser in its place
      -- hijack_netrw = true,
      mappings = {
        ["i"] = {
          -- your custom insert mode mappings
        },
        ["n"] = {
          -- your custom normal mode mappings
			["h"] = fb_actions.goto_parent_dir,
			["l"] = actions.select_default,
        },
      },
    },
  },
}
-- https://github.com/nvim-telescope/telescope-file-browser.nvim
require('telescope').load_extension 'file_browser'
-- open file_browser with the path of the current buffer
vim.api.nvim_set_keymap(
  'n',
  '<space>f',
  ':Telescope file_browser path=%:p:h initial_mode=normal select_buffer=true hidden=true<CR>',
  { noremap = true }
)
