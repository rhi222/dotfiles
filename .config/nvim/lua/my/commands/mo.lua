-- mo: markdownファイルをブラウザでプレビュー
-- https://github.com/k1LoW/mo
-- SECURITY: --bind オプションで非ローカルホストアドレスを指定すると、認証なしでネットワークに公開される。
-- リモートクライアントからファイル読み取り・ファイルシステム探索・サーバー停止が可能になるため、
-- デフォルト（localhost）のまま使用すること。

vim.api.nvim_create_user_command("MoOpen", function()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		vim.notify("MoOpen: ファイルが保存されていません", vim.log.levels.ERROR)
		return
	end
	vim.fn.jobstart("mo " .. vim.fn.shellescape(file), { detach = true })
end, {})

-- markdownファイルでのみキーマップを設定
local keymaps = require("my/plugins/keymaps")
local lhs, mode, desc = keymaps.get("commands", "mo_open")
vim.api.nvim_create_autocmd("FileType", {
	pattern = "markdown",
	callback = function(args)
		vim.keymap.set(mode, lhs, "<cmd>MoOpen<cr>", { buffer = args.buf, desc = desc })
	end,
})
