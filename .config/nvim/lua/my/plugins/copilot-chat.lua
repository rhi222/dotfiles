-- https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#configuration
-- Group all requires at the top
local CopilotChat = require("CopilotChat")
local CopilotActions = require("CopilotChat.actions")
local CopilotChatSelect = require("CopilotChat.select")
local telescope = require("CopilotChat.integrations.telescope")

CopilotChat.setup({
	debug = true,
	prompts = {
		ExplainBuffer = {
			prompt = "/COPILOT_EXPLAIN Write an explanation for the selection as paragraphs of text.",
			selection = CopilotChatSelect.buffer,
		},
	},
	-- CopilotChatModels
	model = "claude-3.7-sonnet"
})

CopilotChatFunctions = {}

-- https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#tips
-- 現在のバッファを読み込んでCopilotChatに質問を投げる関数
CopilotChatFunctions.askCopilotWithBuffer = function()
	local input = vim.fn.input("Quick Chat with Buffer: ")
	if input ~= "" then
		CopilotChat.ask(input, { selection = CopilotChatSelect.buffer })
	end
end
CopilotChatFunctions.askCopilotWithVisual = function()
	local input = vim.fn.input("Quick Chat with Visual: ")
	if input ~= "" then
		CopilotChat.ask(input, { selection = CopilotChatSelect.visual })
	end
end
-- telescopeで選択肢を表示する関数
CopilotChatFunctions.showHelpActionsWithTelescope = function()
	telescope.pick(CopilotActions.help_actions())
end
CopilotChatFunctions.showPromptActionsWithTelescope = function()
	telescope.pick(CopilotActions.prompt_actions())
end

-- CopilotChatOpenのkeymapを設定
vim.keymap.set({ "n", "i", "v" }, "<C-a>", function()
	vim.cmd("CopilotChatOpen")
end)
vim.keymap.set(
	{ "n" },
	"<C-s>",
	"<cmd>lua CopilotChatFunctions.askCopilotWithBuffer()<CR>",
	{ noremap = true, silent = true }
)
vim.keymap.set(
	{ "v" },
	"<C-s>",
	"<cmd>lua CopilotChatFunctions.askCopilotWithVisual()<CR>",
	{ noremap = true, silent = true }
)
--[[ vim.keymap.set(
	{ "n", "i", "v" },
	"<C-d>",
	"<cmd>lua CopilotChatFunctions.showHelpActionsWithTelescope()<CR>",
	{ noremap = true, silent = true }
) ]]
vim.keymap.set(
	{ "n", "i", "v" },
	"<C-d>",
	"<cmd>lua CopilotChatFunctions.showPromptActionsWithTelescope()<CR>",
	{ noremap = true, silent = true }
)
