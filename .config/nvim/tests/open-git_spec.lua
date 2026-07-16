-- OpenGit の URL 生成テスト
-- 実行: tests/test-open-git.sh 経由（nvim --headless -l で起動される）
-- 引数: <config_lua_dir> <target_file> <expected_url_prefix... は環境変数で受け取る>
--   EXPECTED_URL: 期待される完全な URL

local config_lua_dir = _G.arg[1]
local target_file = _G.arg[2]
local expected_url = vim.env.EXPECTED_URL

package.path = config_lua_dir .. "/?.lua;" .. config_lua_dir .. "/?/init.lua;" .. package.path

-- jobstart をスタブしてブラウザ起動を防ぐ
local real_fn = vim.fn
vim.fn = setmetatable({
	jobstart = function()
		return 0
	end,
}, { __index = real_fn })

-- print 出力をキャプチャして URL を取り出す
local outputs = {}
local real_print = print
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end
	outputs[#outputs + 1] = table.concat(parts, " ")
end

require("my.commands.open-git")

vim.cmd.edit(target_file)
vim.cmd("OpenGit")

print = real_print

local actual_url = nil
for _, line in ipairs(outputs) do
	local url = line:match("^Opening URL: (.+)$")
	if url then
		actual_url = url
	end
end

if actual_url == expected_url then
	io.write("PASS\n")
	vim.cmd("cquit 0")
else
	io.write("FAIL\n")
	io.write("  expected: " .. tostring(expected_url) .. "\n")
	io.write("  actual:   " .. tostring(actual_url) .. "\n")
	for _, line in ipairs(outputs) do
		io.write("  output: " .. line .. "\n")
	end
	vim.cmd("cquit 1")
end
