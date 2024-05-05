-- https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#configuration
local CopilotChat = require("CopilotChat")
CopilotChat.setup({
	debug = true,
})

-- CopilotChatOpenのkeymapを設定
vim.keymap.set({ "n" }, "<C-a>", function()
	vim.cmd("CopilotChatOpen")
end)

local CopilotChatSelect = require("CopilotChat.select")

-- https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#tips
-- 現在のバッファを読み込んでCopilotChatに質問を投げる関数
_G.askCopilotWithBuffer = function()
	local input = vim.fn.input("Quick Chat: ")
	if input ~= "" then
		CopilotChat.ask(input, { selection = CopilotChatSelect.buffer })
	end
end

vim.api.nvim_set_keymap("n", "<C-s>", "<cmd>lua _G.askCopilotWithBuffer()<CR>", { noremap = true, silent = true })
