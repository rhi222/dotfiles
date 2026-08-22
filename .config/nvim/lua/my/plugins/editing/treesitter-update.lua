local M = {}

local default_targets = { "stable", "unstable", "unmaintained" }

function M.resolve_targets(languages)
	if #languages == 0 then
		return vim.deepcopy(default_targets)
	end
	return languages
end

function M.update(languages)
	return require("nvim-treesitter").update(M.resolve_targets(languages), { summary = true })
end

local function complete_managed_parsers(arglead)
	local available = {}
	for _, language in ipairs(require("nvim-treesitter.config").get_available()) do
		available[language] = true
	end

	return vim.tbl_filter(function(language)
		return available[language] and language:find(arglead, 1, true) ~= nil
	end, require("nvim-treesitter.config").get_installed())
end

function M.setup_command()
	vim.api.nvim_create_user_command("TSUpdate", function(args)
		M.update(args.fargs)
	end, {
		nargs = "*",
		bar = true,
		complete = complete_managed_parsers,
		desc = "Update nvim-treesitter managed parsers",
	})
end

return M
