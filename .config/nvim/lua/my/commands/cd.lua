-- Go git root
-- fishのabbrと揃えてる
-- https://stackoverflow.com/questions/38081927/vim-cding-to-git-root
vim.api.nvim_create_user_command("Ggr", "exec 'cd' fnameescape(fnamemodify(finddir('.git', escape(expand('%:p:h'), ' ') . ';'), ':h'))", {})
