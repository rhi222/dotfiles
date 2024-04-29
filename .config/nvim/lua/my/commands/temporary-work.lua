vim.api.nvim_create_user_command("Inbox", "edit ~/.inbox.md", {})
vim.api.nvim_create_user_command("Temp", "edit ~/.nvim_tmp/tmp.<args>", { nargs = 1 })
