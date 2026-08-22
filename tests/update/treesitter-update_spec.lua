local config_lua_dir = _G.arg[1]
package.path = config_lua_dir .. "/?.lua;" .. config_lua_dir .. "/?/init.lua;" .. package.path

local calls = {}
package.preload["nvim-treesitter"] = function()
	return {
		update = function(languages, opts)
			calls[#calls + 1] = { languages = languages, opts = opts }
			return true
		end,
	}
end

package.preload["nvim-treesitter.config"] = function()
	return {
		get_available = function()
			return { "bash", "diff" }
		end,
		get_installed = function()
			return { "bash", "diff", "kulala_http" }
		end,
	}
end

local function assert_list(expected, actual, message)
	if not vim.deep_equal(expected, actual) then
		error(string.format("%s: expected=%s actual=%s", message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local update = require("my.plugins.editing.treesitter-update")
update.setup_command()

vim.cmd("TSUpdate")
assert_list({ "stable", "unstable", "unmaintained" }, calls[1].languages, "default targets")
assert(calls[1].opts.summary == true, "summary must remain enabled")

vim.cmd("TSUpdate diff")
assert_list({ "diff" }, calls[2].languages, "explicit target")

local completion = vim.fn.getcompletion("TSUpdate ", "cmdline")
table.sort(completion)
assert_list({ "bash", "diff" }, completion, "managed parser completion")

io.write("PASS\n")
