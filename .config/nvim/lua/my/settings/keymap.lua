-- 非プラグイン（builtin / 環境依存）の global keymap を集約
local km = require("my.plugins.keymaps")

-- nvim 0.12+ builtin: Undotree
do
	local lhs, mode, desc = km.get("builtin", "undotree")
	vim.keymap.set(mode, lhs, vim.cmd.Undotree, { desc = desc })
end

-- WSL固有のkeymap
if vim.fn.has("wsl") == 1 then
	-- xdg-openのtimeout問題を回避するためwslviewを使用
	vim.keymap.set("n", "gx", function()
		local url = vim.fn.expand("<cfile>")
		vim.fn.jobstart({ "wslview", url }, { detach = true })
	end, { silent = true, desc = "Open URL with wslview" })

	-- wslで貼り付けにC-vを割り当てたためremap
	-- Ctrl+Shift+VでVisual Blockモードに入る
	vim.keymap.set({ "n", "v" }, "<C-S-v>", "<C-v>", { silent = true })
end
