-- https://github.com/Saghen/blink.cmp
local km = require("my.plugins.keymaps")

local scroll_up_lhs = km.get("completion", "cmp_scroll_up")
local scroll_down_lhs = km.get("completion", "cmp_scroll_down")
local complete_lhs = km.get("completion", "cmp_complete")
local abort_lhs = km.get("completion", "cmp_abort")
local confirm_lhs = km.get("completion", "cmp_confirm")

require("blink.cmp").setup({
	keymap = {
		preset = "none",
		[scroll_up_lhs] = { "scroll_documentation_up" },
		[scroll_down_lhs] = { "scroll_documentation_down" },
		[complete_lhs] = { "show" },
		[abort_lhs] = { "cancel", "fallback" },
		[confirm_lhs] = { "accept", "fallback" },
		["<Tab>"] = { "select_next", "fallback" },
		["<S-Tab>"] = { "select_prev", "fallback" },
	},
	cmdline = {
		keymap = {
			preset = "none",
			[complete_lhs] = { "show" },
			[abort_lhs] = { "cancel", "fallback" },
			["<CR>"] = { "accept_and_enter", "fallback" },
			["<Tab>"] = { "select_next", "fallback" },
			["<S-Tab>"] = { "select_prev", "fallback" },
		},
	},
	completion = {
		documentation = {
			auto_show = true,
		},
		menu = {
			draw = {
				columns = { { "kind_icon" }, { "label", gap = 1 } },
			},
		},
	},
	sources = {
		default = { "lazydev", "lsp", "path", "buffer" },
		providers = {
			lazydev = {
				name = "LazyDev",
				module = "lazydev.integrations.blink",
				score_offset = 100,
			},
			buffer = {
				fallbacks = { "lsp" },
			},
		},
	},
})
