-- NOTE: eventのdocument
-- nvim events: https://gist.github.com/dtr2300/2f867c2b6c051e946ef23f92bd9d1180
-- lazy.nvim events: https://github.com/folke/lazy.nvim/blob/main/doc/lazy.nvim.txt#L1050-L1070
-- NOTE: vimのmode:
-- https://neovim.io/doc/user/intro.html#_modes,-introduction
-- `:help map-table`で確認可能
-- NOTE: keysのdocument
-- https://github.com/folke/lazy.nvim/blob/main/doc/lazy.nvim.txt#L519-L568

-- カテゴリ別プラグインリストを集約
local plugins = {}
local categories = {
	"my.plugins.ui",
	"my.plugins.lsp",
	"my.plugins.completion",
	"my.plugins.finder",
	"my.plugins.git",
	"my.plugins.editing",
	"my.plugins.tools",
}

for _, mod in ipairs(categories) do
	vim.list_extend(plugins, require(mod))
end

return plugins

-- NOTE: plugin一覧
-- https://github.com/yutkat/my-neovim-pluginlist
