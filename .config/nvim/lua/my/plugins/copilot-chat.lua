-- https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#configuration
-- Group all requires at the top
local CopilotChat = require("CopilotChat")
local CopilotActions = require("CopilotChat.actions")
local CopilotChatSelect = require("CopilotChat.select")
local telescope = require("CopilotChat.integrations.telescope")

CopilotChat.setup({
	debug = true,
	prompts = {},
})

CopilotChatFunctions = {}

-- https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#tips
-- 現在のバッファを読み込んでCopilotChatに質問を投げる関数
CopilotChatFunctions.askCopilotWithBuffer = function()
	local input = vim.fn.input("Quick Chat: ")
	if input ~= "" then
		CopilotChat.ask(input, { selection = CopilotChatSelect.buffer })
	end
end
-- CopilotChat - Help actionsの関数
CopilotChatFunctions.showHelpActionsWithTelescope = function()
	telescope.pick(CopilotActions.help_actions())
end
-- CopilotChat - Prompt actionsの関数
CopilotChatFunctions.showPromptActionsWithTelescope = function()
	telescope.pick(CopilotActions.prompt_actions())
end

-- CopilotChatOpenのkeymapを設定
vim.keymap.set({ "n", "i", "v" }, "<C-a>", function()
	vim.cmd("CopilotChatOpen")
end)
vim.keymap.set(
	{ "n", "i", "v" },
	"<C-s>",
	"<cmd>lua CopilotChatFunctions.askCopilotWithBuffer()<CR>",
	{ noremap = true, silent = true }
)
vim.keymap.set(
	{ "n", "i", "v" },
	"<C-d>",
	"<cmd>lua CopilotChatFunctions.showHelpActionsWithTelescope()<CR>",
	{ noremap = true, silent = true }
)
vim.keymap.set(
	{ "n", "i", "v" },
	"<C-f>",
	"<cmd>lua CopilotChatFunctions.showPromptActionsWithTelescope()<CR>",
	{ noremap = true, silent = true }
)
