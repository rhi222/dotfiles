-- https://github.com/hrsh7th/nvim-cmp
local km = require("my.plugins.keymaps")
local cmp = require("cmp")

local scroll_up_lhs = km.get("completion", "cmp_scroll_up")
local scroll_down_lhs = km.get("completion", "cmp_scroll_down")
local complete_lhs = km.get("completion", "cmp_complete")
local abort_lhs = km.get("completion", "cmp_abort")
local confirm_lhs = km.get("completion", "cmp_confirm")

cmp.setup({
	snippet = {
		-- REQUIRED - you must specify a snippet engine
		expand = function(args)
			vim.fn["vsnip#anonymous"](args.body) -- For `vsnip` users.
		end,
	},
	mapping = cmp.mapping.preset.insert({
		[scroll_up_lhs] = cmp.mapping.scroll_docs(-4),
		[scroll_down_lhs] = cmp.mapping.scroll_docs(4),
		[complete_lhs] = cmp.mapping.complete(),
		[abort_lhs] = cmp.mapping.abort(),
		[confirm_lhs] = cmp.mapping.confirm({ select = true }),
	}),
	sources = cmp.config.sources({
		{ name = "copilot" },
		{ name = "nvim_lsp" },
		{ name = "vsnip" }, -- For vsnip users.
	}, {
		{ name = "buffer" },
	}),
})
-- Set configuration for specific filetype.
cmp.setup.filetype("gitcommit", {
	sources = cmp.config.sources({
		{ name = "git" }, -- You can specify the `git` source if [you were installed it](https://github.com/petertriho/cmp-git).
	}, {
		{ name = "buffer" },
	}),
})

-- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
cmp.setup.cmdline({ "/", "?" }, {
	mapping = cmp.mapping.preset.cmdline(),
	sources = {
		{ name = "buffer" },
	},
})

-- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
cmp.setup.cmdline(":", {
	mapping = cmp.mapping.preset.cmdline(),
	sources = cmp.config.sources({ { name = "path" } }, { { name = "cmdline" } }),
})
