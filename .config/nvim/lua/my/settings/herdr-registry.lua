local M = {}

local initial_pane = vim.env.HERDR_PANE_ID
local state_dir = (vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state")) .. "/herdr-nvim"
local owner = string.format("%d-%x", vim.fn.getpid(), vim.uv.hrtime())
local marker = state_dir .. "/" .. owner .. ".json"
local current_pane = initial_pane
local session_tag = vim.env.HERDR_RESTORE_SESSION_TAG or initial_pane
local active = false
local refresh_running = false

local function is_headless()
	if vim.env.HERDR_NVIM_REGISTRY_TEST == "1" then
		return false
	end
	return not next(vim.api.nvim_list_uis())
end

local function marker_kind()
	local args = vim.fn.argv()
	if #args > 0 then
		return "files", args
	end
	return "session", nil
end

local function write_marker()
	if not active or not current_pane or current_pane == "" then
		return
	end
	local kind, args = marker_kind()
	local record = {
		version = 2,
		owner = owner,
		pane_id = current_pane,
		socket_path = vim.env.HERDR_SOCKET_PATH or "",
		cwd = vim.fn.getcwd(-1, -1),
		kind = kind,
		args = args,
		session_tag = session_tag,
	}
	vim.fn.mkdir(state_dir, "p")
	local tmp = marker .. ".tmp"
	if vim.fn.writefile({ vim.json.encode(record) }, tmp) == 0 then
		vim.uv.fs_rename(tmp, marker)
	end
end

-- `pane move` changes the public pane id but cannot rewrite an already running
-- process's environment. Herdr resolves --current from the inherited caller
-- context, so query it periodically and update only this owner's record.
local function refresh_pane()
	if not active or refresh_running then
		return
	end
	local herdr = vim.env.HERDR_BIN_PATH or "herdr"
	if vim.fn.executable(herdr) ~= 1 then
		return
	end
	refresh_running = true
	vim.system({ herdr, "pane", "current", "--current" }, { text = true }, function(result)
		vim.schedule(function()
			refresh_running = false
			if result.code ~= 0 then
				return
			end
			local ok, decoded = pcall(vim.json.decode, result.stdout or "")
			local pane = ok and decoded and decoded.result and decoded.result.pane
			if pane and pane.pane_id and pane.pane_id ~= "" then
				current_pane = pane.pane_id
				write_marker()
			end
		end)
	end)
end

function M.session_saved()
	-- A moved/restored process reads the old tag once, then saves under the pane
	-- id inherited by the newly launched nvim. Record which copy is now current.
	session_tag = initial_pane
	write_marker()
end

function M.setup()
	if not initial_pane or initial_pane == "" then
		return
	end
	local grp = vim.api.nvim_create_augroup("herdr_nvim_registry", {})
	vim.api.nvim_create_autocmd("VimEnter", {
		group = grp,
		callback = function()
			if is_headless() or vim.g.in_pager_mode then
				return
			end
			active = true
			write_marker()
			refresh_pane()
		end,
	})
	vim.api.nvim_create_autocmd({ "FocusGained", "DirChanged" }, {
		group = grp,
		callback = refresh_pane,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = grp,
		callback = function()
			if active and vim.v.dying == 0 then
				vim.fn.delete(marker)
			end
		end,
	})

	local timer = vim.uv.new_timer()
	timer:start(10000, 10000, vim.schedule_wrap(refresh_pane))
end

return M
