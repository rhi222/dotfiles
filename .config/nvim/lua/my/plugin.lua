-- NOTE: eventのdocument
-- nvim events: https://gist.github.com/dtr2300/2f867c2b6c051e946ef23f92bd9d1180
-- lazy.nvim events: https://github.com/folke/lazy.nvim/blob/main/doc/lazy.nvim.txt#L1050-L1070
-- NOTE: vimのmode:
-- https://neovim.io/doc/user/intro.html#_modes,-introduction
-- `:help map-table`で確認可能
-- NOTE: keysのdocument
-- https://github.com/folke/lazy.nvim/blob/main/doc/lazy.nvim.txt#L519-L568
-- FIXME: key map再考
-- https://zenn.dev/vim_jp/articles/2023-05-19-vim-keybind-philosophy
-- https://zenn.dev/nil2/articles/802f115673b9ba
-- https://maku77.github.io/vim/keymap/current-map.html
-- https://stackoverflow.com/questions/2239226/saving-output-of-map-in-vim

-- カテゴリ別プラグインリストを集約
local plugins = {}
local categories = {
	"my.plugins.list.ui",
	"my.plugins.list.lsp",
	"my.plugins.list.completion",
	"my.plugins.list.finder",
	"my.plugins.list.git",
	"my.plugins.list.editing",
	"my.plugins.list.misc",
}

for _, mod in ipairs(categories) do
	local list = require(mod)
	for _, plugin in ipairs(list) do
		table.insert(plugins, plugin)
	end
end

return plugins

-- NOTE: plugin一覧
-- https://github.com/yutkat/my-neovim-pluginlist
