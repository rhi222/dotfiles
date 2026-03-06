-- https://github.com/Saghen/blink.cmp
local km = require("my.plugins.keymaps")

local scroll_up_lhs = km.get("completion", "cmp_scroll_up")
local scroll_down_lhs = km.get("completion", "cmp_scroll_down")
local complete_lhs = km.get("completion", "cmp_complete")
local abort_lhs = km.get("completion", "cmp_abort")
local confirm_lhs = km.get("completion", "cmp_confirm")
local select_next_lhs = km.get("completion", "cmp_select_next")
local select_prev_lhs = km.get("completion", "cmp_select_prev")

require("blink.cmp").setup({
	keymap = {
		preset = "default",
		[scroll_up_lhs] = { "scroll_documentation_up", "fallback" },
		[scroll_down_lhs] = { "scroll_documentation_down", "fallback" },
		[complete_lhs] = { "show" },
		[abort_lhs] = { "cancel", "fallback" },
		[confirm_lhs] = { "accept", "fallback" },
		[select_next_lhs] = { "select_next", "fallback_to_mappings" },
		[select_prev_lhs] = { "select_prev", "fallback_to_mappings" },
	},
	cmdline = {
		keymap = {
			preset = "inherit",
			[confirm_lhs] = { "accept_and_enter", "fallback" },
		},
		completion = {
			list = {
				selection = { preselect = false, auto_insert = false },
			},
			menu = {
				auto_show = function()
					return vim.fn.getcmdtype() == ":"
				end,
			},
		},
	},
	completion = {
		list = {
			selection = { preselect = false, auto_insert = false },
		},
		documentation = {
			auto_show = true,
			auto_show_delay_ms = 200,
		},
		menu = {
			draw = {
				columns = { { "kind_icon" }, { "label", gap = 1 } },
			},
		},
	},
	signature = { enabled = true },
	sources = {
		default = { "lsp", "path", "snippets", "buffer" },
		per_filetype = {
			lua = { inherit_defaults = true, "lazydev" },
		},
		providers = {
			lazydev = {
				name = "LazyDev",
				module = "lazydev.integrations.blink",
				score_offset = 100,
			},
			-- lspのデフォルト: fallbacks = { "buffer" }
			-- LSP結果がない場合のみbufferが表示される（nvim-cmpのgroup動作と同等）
		},
	},
})
