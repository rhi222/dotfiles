-- https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#configuration
-- Group all requires at the top
local chat = require("CopilotChat")
local actions = require("CopilotChat.actions")
local select = require("CopilotChat.select")
local telescope = require("CopilotChat.integrations.telescope")

chat.setup({
	debug = true,
	prompts = {
		ExplainBuffer = {
			prompt = "/COPILOT_EXPLAIN Write an explanation for the selection as paragraphs of text.",
			selection = select.buffer,
		},
	},
	-- CopilotChatModels
	model = "claude-3.7-sonnet"
})

-- 公式: https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#lazynvim
-- が紹介している、以下レポジトリを参考にしてコマンド定義
-- https://github.com/jellydn/lazy-nvim-ide/blob/main/lua/plugins/extras/copilot-chat-v2.lua

-- 選択範囲（Visual）でCopilotChatに質問するコマンド
vim.api.nvim_create_user_command("CopilotChatVisual", function(args)
  chat.ask(args.args, { selection = select.visual })
end, { nargs = "*", range = true })


-- Inline chat with Copilot
vim.api.nvim_create_user_command("CopilotChatInline", function(args)
  chat.ask(args.args, {
    selection = select.visual,
    window = {
      layout = "float",
      relative = "cursor",
      width = 1,
      height = 0.4,
      row = 1,
    },
  })
end, { nargs = "*", range = true })

-- Restore CopilotChatBuffer
vim.api.nvim_create_user_command("CopilotChatBuffer", function(args)
  chat.ask(args.args, { selection = select.buffer })
end, { nargs = "*", range = true })

-- Custom buffer for CopilotChat
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "copilot-*",
  callback = function()
    vim.opt_local.relativenumber = true
    vim.opt_local.number = true

    -- Get current filetype and set it to markdown if the current filetype is copilot-chat
    local ft = vim.bo.filetype
    if ft == "copilot-chat" then
      vim.bo.filetype = "markdown"
    end
  end,
})

-- Telescopeでプロンプトアクションの選択肢を表示するコマンド
vim.api.nvim_create_user_command("CopilotChatShowPrompt", function()
	telescope.pick(actions.prompt_actions())
end, { nargs = 0 })

-- Telescopeでヘルプアクションの選択肢を表示するコマンド
vim.api.nvim_create_user_command("CopilotChatShowHelp", function()
	telescope.pick(actions.help_actions())
end, { nargs = 0 })

-- キーマッピングの例（必要に応じてお好みで設定してください）
vim.keymap.set("n", "<C-s>", ":CopilotChatBuffer<CR>", { noremap = true, silent = true })
vim.keymap.set("v", "<C-s>", ":CopilotChatVisual<CR>", { noremap = true, silent = true })
vim.keymap.set({ "n", "i", "v" }, "<C-d>", ":CopilotChatShowPrompt<CR>", { noremap = true, silent = true })
-- ヘルプアクションを使う場合は以下のように設定できます
-- vim.keymap.set({ "n", "i", "v" }, "<C-d>", ":CopilotChatShowHelp<CR>", { noremap = true, silent = true })
