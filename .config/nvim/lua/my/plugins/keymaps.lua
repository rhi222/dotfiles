-- keymap中央レジストリ
-- lhs（キー割り当て）、mode、desc をカテゴリ別に定義
-- rhs（アクション）は各spec/configに残す（プラグインAPIに依存するため）
local M = {}

-- ============================================================
-- PREFIX MAP (空きキー一覧)
-- ============================================================
-- <leader>(Space) + 1char:
--   使用中: g(neogit) j(hop) m(quickhl)
--   空き:   a b c d e f h i k l n o p q r s t u v w x y z
--
-- <leader> + 2char:
--   使用中: cp cd(copilot) gb(blame) og(git-url)
--           st ss sd se sf sv sp sc(sidekick)
--   空き:   ga gc gd ge gf... など多数
--
-- <C-p> + char (Finder):
--   使用中: f e g l p : m s c r b o h d
--   空き:   a i j k n q t u v w x y z
--
-- <space> + char (LSP/Diagnostics):
--   使用中: e f q D
--   空き:   a b c d g h i j k l m n o p r s t u v w x y z
--
-- g + char (Go-to/Motion):
--   使用中: d D i r(LSP:ref) s S R(flash) c b(comment)
--   空き:   a e f g h j k l m n o p q t u v w x y z

-- ============================================================
-- 各カテゴリのkeymap定義
-- { lhs, mode = "n"|{"n","v"}, desc = "..." }
-- mode省略時は "n"
-- ============================================================

M.finder = {
	telescope_file_browser = { "<space>f", desc = "file_browser" },
	telescope_find_files = { "<C-p>f", desc = "Find files" },
	telescope_smart_open = { "<C-p>e", desc = "Smart open" },
	telescope_live_grep = { "<C-p>g", desc = "Live grep (egrepify)" },
	telescope_fuzzy_find = { "<C-p>l", desc = "Buffer fuzzy find" },
	telescope_commands = { "<C-p>p", desc = "Commands" },
	telescope_cmd_history = { "<C-p>:", desc = "Command history" },
	telescope_bookmarks = { "<C-p>m", desc = "Vim bookmarks" },
	telescope_symbols = { "<C-p>s", desc = "LSP workspace symbols" },
	telescope_git_status = { "<C-p>c", desc = "Git status" },
	telescope_resume = { "<C-p>r", desc = "Resume last picker" },
	telescope_buffers = { "<C-p>b", desc = "Buffers" },
	telescope_oldfiles = { "<C-p>o", desc = "Old files" },
	telescope_help = { "<C-p>h", desc = "Help tags" },
	telescope_diagnostics = { "<C-p>d", desc = "Diagnostics" },
	fzf_grep = { "<c-g>", desc = "FZF grep" },
}

M.lsp = {
	diagnostic_float = { "<space>e", desc = "Diagnostic float" },
	diagnostic_prev = { "[d", desc = "Previous diagnostic" },
	diagnostic_next = { "]d", desc = "Next diagnostic" },
	diagnostic_loclist = { "<space>q", desc = "Diagnostics to loclist" },
	declaration = { "gD", desc = "Declaration" },
	definition = { "gd", desc = "Definition" },
	hover = { "K", desc = "Hover" },
	implementation = { "gi", desc = "Implementation" },
	signature_help = { "<C-k>", desc = "Signature help" },
	workspace_add = { "<space>wa", desc = "Add workspace folder" },
	workspace_remove = { "<space>wr", desc = "Remove workspace folder" },
	workspace_list = { "<space>wl", desc = "List workspace folders" },
	type_definition = { "<space>D", desc = "Type definition" },
	rename = { "<space>rn", desc = "Rename" },
	code_action = { "<space>ca", mode = { "n", "v" }, desc = "Code action" },
	references = { "gr", desc = "References" },
}

M.completion = {
	copilot_accept = { "<C-y>", mode = "i", desc = "Copilot: Accept" },
	copilot_next = { "<C-l>", mode = "i", desc = "Copilot: Next" },
	copilot_prev = { "<C-h>", mode = "i", desc = "Copilot: Previous" },
	copilot_dismiss = { "<C-]>", mode = "i", desc = "Copilot: Dismiss" },
	chat_prompts_n = { "<leader>cp", desc = "CopilotChat Prompts" },
	chat_prompts_x = { "<leader>cp", mode = "x", desc = "CopilotChat Prompts" },
	chat_show_prompt = { "<leader>cd", mode = { "x", "n", "i" }, desc = "CopilotChat Show" },
	cmp_scroll_up = { "<C-b>", mode = "i", desc = "Scroll docs up" },
	cmp_scroll_down = { "<C-f>", mode = "i", desc = "Scroll docs down" },
	cmp_complete = { "<C-Space>", mode = "i", desc = "Trigger completion" },
	cmp_abort = { "<C-e>", mode = "i", desc = "Abort completion" },
	cmp_confirm = { "<CR>", mode = "i", desc = "Confirm completion" },
}

M.git = {
	neogit_open = { "<leader>g", desc = "Open neogit" },
	toggle_blame = { "<leader>gb", desc = "Toggle line blame" },
}

M.editing = {
	hop_word = { "<leader>j", desc = "Hop word" },
	flash_jump = { "gs", mode = { "n", "x", "o" }, desc = "Flash jump" },
	flash_treesitter = { "gS", mode = { "n", "x", "o" }, desc = "Flash treesitter" },
	flash_remote = { "gr", mode = "o", desc = "Flash remote" },
	flash_ts_search = { "gR", mode = { "o", "x" }, desc = "Flash treesitter search" },
	flash_toggle = { "<c-s>", mode = "c", desc = "Toggle Flash" },
	quickhl_this = { "<leader>m", desc = "Quickhl highlight" },
}

M.tools = {
	rest_run = { "<C-e>", desc = "Rest run" },
	sidekick_jump = { "<tab>", desc = "Sidekick jump/apply" },
	sidekick_toggle = { "<c-.>", mode = { "n", "t", "i", "x" }, desc = "Sidekick toggle" },
	sidekick_toggle2 = { "<leader>st", desc = "Sidekick toggle CLI" },
	sidekick_select = { "<leader>ss", desc = "Sidekick select CLI" },
	sidekick_close = { "<leader>sd", desc = "Sidekick detach" },
	sidekick_send = { "<leader>se", mode = { "x", "n" }, desc = "Sidekick send this" },
	sidekick_file = { "<leader>sf", desc = "Sidekick send file" },
	sidekick_visual = { "<leader>sv", mode = "x", desc = "Sidekick send selection" },
	sidekick_prompt = { "<leader>sp", mode = { "n", "x" }, desc = "Sidekick prompt" },
	sidekick_claude = { "<leader>sc", desc = "Sidekick toggle Claude" },
}

M.commands = {
	open_git = { "<leader>og", desc = "Open Git URL" },
	open_git_visual = { "<leader>og", mode = "v", desc = "Open Git URL (visual)" },
}

-- ============================================================
-- ヘルパー関数
-- ============================================================

--- キー情報を取得 (lhs, mode, desc)
---@param category string カテゴリ名
---@param name string キーマップ名
---@return string lhs, string|table mode, string desc
function M.get(category, name)
	local entry = M[category] and M[category][name]
	if not entry then
		error("Unknown keymap: " .. category .. "." .. name)
	end
	return entry[1], entry.mode or "n", entry.desc
end

--- lazy.nvim keys spec用エントリを生成
---@param category string カテゴリ名
---@param name string キーマップ名
---@param rhs string|function アクション
---@param opts? table 追加オプション
---@return table lazy_key lazy.nvim keys specエントリ
function M.lazy_key(category, name, rhs, opts)
	local lhs, mode, desc = M.get(category, name)
	return vim.tbl_extend("force", {
		lhs,
		rhs,
		mode = type(mode) == "string" and { mode } or mode,
		desc = desc,
	}, opts or {})
end

--- 全keymapの重複を検出
---@return table duplicates {lhs_mode = {category.name, ...}, ...}
function M.find_duplicates()
	local seen = {}
	local duplicates = {}
	for cat_name, entries in pairs(M) do
		if type(entries) == "table" and cat_name ~= "commands" then
			for key_name, entry in pairs(entries) do
				if type(entry) == "table" and entry[1] then
					local modes = entry.mode or "n"
					if type(modes) == "string" then
						modes = { modes }
					end
					for _, m in ipairs(modes) do
						local id = entry[1] .. ":" .. m
						if not seen[id] then
							seen[id] = {}
						end
						table.insert(seen[id], cat_name .. "." .. key_name)
					end
				end
			end
		end
	end
	for id, names in pairs(seen) do
		if #names > 1 then
			duplicates[id] = names
		end
	end
	return duplicates
end

return M
