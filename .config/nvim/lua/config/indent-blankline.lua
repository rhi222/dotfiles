-- https://github.com/lukas-reineke/indent-blankline.nvim
vim.opt.list = true
-- vim.cmd [[highlight IndentBlanklineIndent guifg=#E06C75 gui=nocombine]]
-- vim.opt.listchars:append "space:⋅"
-- vim.opt.listchars:append "eol:↴"

require("indent_blankline").setup {
    -- show_current_context = true,
    -- show_current_context_start = true,
    char = '|',
    show_end_of_line = true,
    show_trailing_blankline_indent = false,
    -- char_highlight_list = {
    --     "IndentBlanklineIndent",
    -- },
    -- -- space_char_blankline = " ",
}
