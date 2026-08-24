-- 非プラグイン（builtin / 環境依存）の global keymap を集約
local km = require("my.plugins.keymaps")

-- nvim 0.12+ builtin: Undotree
do
	local lhs, mode, desc = km.get("builtin", "undotree")
	vim.keymap.set(mode, lhs, vim.cmd.Undotree, { desc = desc })
end

-- nvim 0.12 の ZR（= :restart）を潰す。
-- zR（全fold展開）とシフト1つ違いで、nvim-treesitter.lua で filetype 単位に
-- treesitter fold を有効にしているため zR は日常的に打つ。0.12.5 から :restart は
-- mksession とセッション復元まで走るので、誤爆の代償が上がった。
-- 再起動したいときは :restart を明示的に打つ。count 付きの 9ZR 等もこれで塞がる。
vim.keymap.set("n", "ZR", "<Nop>", { desc = "Disabled: ZR(:restart) は zR の誤爆になりやすい" })

-- WSL固有のkeymap
if vim.fn.has("wsl") == 1 then
	-- xdg-openのtimeout問題を回避するためwslviewを使用
	vim.keymap.set("n", "gx", function()
		local url = vim.fn.expand("<cfile>")
		vim.fn.jobstart({ "wslview", url }, { detach = true })
	end, { silent = true, desc = "Open URL with wslview" })
end
