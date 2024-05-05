-- https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#configuration
-- Group all requires at the top
local CopilotChat = require("CopilotChat")
local CopilotChatSelect = require("CopilotChat.select")
local copilotActions = require("CopilotChat.actions")
local telescope = require("CopilotChat.integrations.telescope")

CopilotChat.setup({
	debug = true,
	prompts = {},
})

-- CopilotChatOpenのkeymapを設定
vim.keymap.set({ "n" }, "<C-a>", function()
	vim.cmd("CopilotChatOpen")
end)

-- https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#tips
-- 現在のバッファを読み込んでCopilotChatに質問を投げる関数
_G.askCopilotWithBuffer = function()
	local input = vim.fn.input("Quick Chat: ")
	if input ~= "" then
		CopilotChat.ask(input, { selection = CopilotChatSelect.buffer })
	end
end

vim.api.nvim_set_keymap("n", "<C-s>", "<cmd>lua _G.askCopilotWithBuffer()<CR>", { noremap = true, silent = true })

-- CopilotChat.actionsをrequire
local actions = require("CopilotChat.actions")

-- CopilotChat - Help actionsの関数
_G.showHelpActionsWithTelescope = function()
	telescope.pick(actions.help_actions())
end

-- CopilotChat - Prompt actionsの関数
_G.showPromptActionsWithTelescope = function()
	telescope.pick(actions.prompt_actions())
end

-- 新しい関数をキーマップに追加
vim.api.nvim_set_keymap(
	"n",
	"<C-d>",
	"<cmd>lua _G.showHelpActionsWithTelescope()<CR>",
	{ noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
	"n",
	"<C-f>",
	"<cmd>lua _G.showPromptActionsWithTelescope()<CR>",
	{ noremap = true, silent = true }
)
