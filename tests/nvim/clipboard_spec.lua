-- WSLのクリップボード設定（vim.g.clipboard）が実際に動くかを確かめる。
--
-- 設定文字列を写して固定するのではなく、書かれたコマンドをそのまま走らせる。
-- win32yank のフラグは方向ごとに違い（`-o [--lf]` / `-i [--crlf]`）、無効な組み合わせは
-- exit 1 で落ちる。clipboard = unnamedplus なのでヤンクと貼り付けが全部この provider を
-- 通る。読み出しが落ちると nvim の貼り付けが丸ごと空になる。
local config_dir = _G.arg[1]
package.path = config_dir .. "/lua/?.lua;" .. config_dir .. "/lua/?/init.lua;" .. package.path

assert(vim.fn.has("wsl") == 1, "このテストはWSL上で実行すること")

require("my.settings.option")

local cb = vim.g.clipboard
assert(cb ~= nil, "WSLでは vim.g.clipboard が設定されること")

local registers = { "+", "*" }

-- 読み出しは副作用が無いので、そのまま走らせて成否を見る。
for _, reg in ipairs(registers) do
	local cmd = cb.paste[reg]
	assert(cmd ~= nil, string.format('paste["%s"] が設定されていない', reg))
	local out = vim.fn.system(cmd)
	assert(
		vim.v.shell_error == 0,
		string.format('paste["%s"] = %s が失敗した (exit %d): %s', reg, vim.inspect(cmd), vim.v.shell_error, out)
	)
end

-- 書き込みは「今ある内容をそのまま書き戻す」ことで、クリップボードを壊さずに確かめる。
-- 空のとき（テキスト以外を持っている場合を含む）は書き込まない。
--
-- **クリップボードは実機の共有状態なので、書き込みはこの書き戻しに限る。** 読み出しと
-- 書き戻しの間に人がコピーすると、その1回分が巻き戻る。窓は数ミリ秒だが0ではない。
-- それでも書き込み側を落とさないのは、--crlf/--lf の対が噛み合っているかを
-- 往復の一致でしか確かめられないため。
local before = vim.fn.system(cb.paste["+"])
if before ~= "" then
	for _, reg in ipairs(registers) do
		local cmd = cb.copy[reg]
		assert(cmd ~= nil, string.format('copy["%s"] が設定されていない', reg))
		local out = vim.fn.system(cmd, before)
		assert(
			vim.v.shell_error == 0,
			string.format(
				'copy["%s"] = %s が失敗した (exit %d): %s',
				reg,
				vim.inspect(cmd),
				vim.v.shell_error,
				out
			)
		)
	end

	local after = vim.fn.system(cb.paste["+"])
	assert(after == before, "書き戻しでクリップボードの内容が変わった")
end

io.write("PASS\n")
