-- https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#configuration
require("CopilotChat").setup({
	debug = true,
})

-- CopilotChatOpenのkeymapを設定
vim.keymap.set({ "n" }, "<C-a>", function()
	vim.cmd("CopilotChatOpen")
end)
