-- nvim 0.12.5 の `:restart`（bang なし）は nvim 自身が mksession でセッションを保存し、
-- 再起動後、UI アタッチ後にそれを source する（`:h :restart` の手順1と4）。
-- auto-session は v:startreason を見ないため、素のままだと auto_restore（VimEnter）と
-- nvim 本体の source が両方走り、バッファリストが2セッション分の和になる。さらに
-- 定期保存がその和をプロジェクトセッションへ焼き付ける。
--
-- 固定する不変条件:
--   1. 起動理由 → auto-session に復元させてよいかの対応。restart 系は復元させない
--      （`:restart!` は「復元しない」指定なので、ここで復元すると指定が潰れる）
--   2. auto-session.lua がその判定を auto_restore へ配線している
--   3. 同じ判定を no_restore_cmds の cwd フォールバックへも配線している。
--      auto_restore = false でも auto-session は no_restore を発火するため
--      （auto-session/init.lua の auto_restore_session_at_vim_enter 末尾）、
--      ここを塞がないとフォールバック側から二重復元が復活する

local config_dir = _G.arg[1]
package.path = config_dir .. "/lua/?.lua;" .. config_dir .. "/lua/?/init.lua;" .. package.path

local AUTOSESSION_LUA = config_dir .. "/lua/my/plugins/tools/auto-session.lua"
local GUARD_MODULE = "my.plugins.tools.session-start"

local failures = {}

local function check(cond, msg)
	if not cond then
		table.insert(failures, msg)
	end
end

-- --- 1. 起動理由の判定 ---

local session_start = require(GUARD_MODULE)

for _, case in ipairs({
	{ reason = "normal", allow = true },
	{ reason = "restart", allow = false },
	{ reason = "restart!", allow = false },
	-- v:startreason は 0.12.5 で追加された。未定義バージョンでは nil が返るため、
	-- 従来どおり復元する側へ倒す
	{ reason = nil, allow = true },
}) do
	check(
		session_start.should_auto_restore(case.reason) == case.allow,
		("should_auto_restore(%s) は %s であるべき"):format(vim.inspect(case.reason), tostring(case.allow))
	)
end

-- --- 2, 3. auto-session.lua への配線 ---

-- 実物の auto-session.lua を読み込み、setup() に渡る opts を捕まえる。
-- プラグイン本体は入れず、判定モジュールだけ差し替えて両方の分岐を作る。
-- v:startreason は read-only で外から与えられないため、判定の入口を差し替える。
local function load_autosession(is_normal_start, root_dir)
	local captured = {}
	local restored = {}

	package.loaded["auto-session"] = {
		setup = function(opts)
			captured.opts = opts
		end,
		get_root_dir = function()
			return root_dir
		end,
		restore_session_file = function(path)
			table.insert(restored, path)
		end,
		auto_save_session = function() end,
	}
	package.loaded["auto-session.lib"] = {
		remove_trailing_separator = function(s)
			return s
		end,
		escape_session_name = function()
			return "SESSION"
		end,
	}
	package.loaded["auto-session.config"] = { resolve_symlinks = false }
	package.loaded[GUARD_MODULE] = {
		should_auto_restore = session_start.should_auto_restore,
		is_normal_start = function()
			return is_normal_start
		end,
	}

	-- フォールバックは herdr ペイン内でのみ走る
	vim.env.HERDR_PANE_ID = "w1:p1"
	-- auto-session の headless 判定を外すための公式のテスト用フラグ。
	-- これが無いと is_headless() が true になりフォールバックが早期 return する
	vim.env.AUTOSESSION_UNIT_TESTING = "1"

	dofile(AUTOSESSION_LUA)

	package.loaded[GUARD_MODULE] = session_start
	return captured.opts, restored
end

-- restart 由来の起動: auto_restore を落とし、フォールバックも走らせない
do
	local tmp = vim.fn.tempname()
	vim.fn.mkdir(tmp, "p")
	-- 「セッションファイルが実在しても復元しない」ことを見るため、実体を置く
	vim.fn.writefile({ "" }, tmp .. "/SESSION.vim")

	local opts, restored = load_autosession(false, tmp .. "/")
	check(opts ~= nil, "auto-session.setup() が呼ばれていない")
	if opts then
		check(opts.auto_restore == false, "restart 由来の起動では auto_restore を false にすべき")
		check(type(opts.no_restore_cmds) == "table" and #opts.no_restore_cmds > 0, "no_restore_cmds が空")
		for _, cmd in ipairs(opts.no_restore_cmds or {}) do
			cmd()
		end
		check(
			#restored == 0,
			("restart 由来の起動では cwd フォールバックを走らせるべきでない（復元: %s）"):format(
				vim.inspect(restored)
			)
		)
	end
end

-- 通常起動: 従来どおり復元する（ガードがやりすぎでないこと）
do
	local tmp = vim.fn.tempname()
	vim.fn.mkdir(tmp, "p")
	local session_file = tmp .. "/SESSION.vim"
	vim.fn.writefile({ "" }, session_file)

	local opts, restored = load_autosession(true, tmp .. "/")
	check(opts ~= nil, "auto-session.setup() が呼ばれていない")
	if opts then
		check(opts.auto_restore == true, "通常起動では auto_restore を true にすべき")
		for _, cmd in ipairs(opts.no_restore_cmds or {}) do
			cmd()
		end
		check(
			#restored == 1 and restored[1] == session_file,
			("通常起動では cwd フォールバックが走るべき（復元: %s）"):format(
				vim.inspect(restored)
			)
		)
	end
end

if #failures > 0 then
	for _, msg in ipairs(failures) do
		io.write("FAIL: " .. msg .. "\n")
	end
	os.exit(1)
end

io.write("PASS\n")
