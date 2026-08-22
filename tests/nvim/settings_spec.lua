local config_dir = _G.arg[1]
package.path = config_dir .. "/lua/?.lua;" .. config_dir .. "/lua/?/init.lua;" .. package.path

require("my.settings.autocmd")

local function assert_indent(filetype, expandtab, width)
	vim.bo.filetype = ""
	vim.bo.expandtab = not expandtab
	vim.bo.shiftwidth = 8
	vim.bo.softtabstop = 8
	vim.bo.tabstop = 8
	vim.bo.filetype = filetype

	assert(vim.bo.expandtab == expandtab, string.format("%s: unexpected expandtab", filetype))
	assert(vim.bo.shiftwidth == width, string.format("%s: unexpected shiftwidth", filetype))
	assert(vim.bo.softtabstop == width, string.format("%s: unexpected softtabstop", filetype))
	assert(vim.bo.tabstop == width, string.format("%s: unexpected tabstop", filetype))
end

for _, case in ipairs({
	{ "markdown", 4 },
	{ "typescript", 4 },
	{ "yaml", 2 },
	{ "python", 4 },
	{ "unknown_test_filetype", 4 },
}) do
	assert_indent(case[1], true, case[2])
end

for _, filetype in ipairs({ "go", "gomod", "gowork", "make", "tsv" }) do
	assert_indent(filetype, false, 4)
end

local ts_config = dofile(config_dir .. "/lsp/ts_ls.lua")
assert(
	vim.deep_equal(ts_config.root_markers, {
		{ "tsconfig.json", "jsconfig.json", "package.json" },
	}),
	"TypeScript root markers must have equal priority"
)

io.write("PASS\n")
