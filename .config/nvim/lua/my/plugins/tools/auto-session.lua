-- 起動時の引数の数。setup() より前に取っておく。
-- auto-session も同じ理由（NvimTree 等が引数を書き換える前に見る必要がある）で
-- setup() の中で argv を控えており、ここは同じタイミングになる。
local launch_argc = #vim.fn.argv()

-- auto-session の headless 判定（init.lua の in_headless_mode）に合わせる。
-- テスト用の解除フラグまで含めて揃えないと、headless で駆動しているテストから
-- フォールバックの挙動を確認できなくなる。
-- --embed のクライアントは UI の attach が後になるため headless 扱いしない。
local function is_headless()
	if vim.env.AUTOSESSION_UNIT_TESTING then
		return false
	end
	return not vim.tbl_contains(vim.v.argv, "--embed") and not next(vim.api.nvim_list_uis())
end

require("auto-session").setup({
	enabled = true,
	auto_save = true,
	auto_restore = true,
	show_auto_restore_notif = true,
	suppressed_dirs = {
		vim.fn.expand("~"),
		vim.fn.expand("~/Downloads"),
		"/",
	},
	-- `nvim somefile` の終了時にプロジェクトセッションを上書きしないよう無効化。
	-- ファイル引数付き起動はセッション保存対象外とし、素のnvim起動のみ保存する。
	args_allow_files_auto_save = false,
	-- 削除済みworktree等の孤児セッションファイルを自動削除（30日）
	purge_after_minutes = 43200,
	-- herdr のペイン単位でセッションを分ける。
	-- auto-session のセッション名は cwd 由来のため、同じ cwd で複数ペインを開くと
	-- 1つのセッションファイルを共有し、最後に保存したペインの状態で上書きされる。
	-- ペイン ID をタグとして混ぜ、ペインごとに別の状態で復元できるようにする。
	-- herdr の外で起動した nvim は nil を返して従来どおり cwd 単位になる。
	custom_session_tag = function()
		local pane = vim.env.HERDR_PANE_ID
		if pane and pane ~= "" then
			return pane
		end
		return nil
	end,
	-- タグ付きのセッションが見つからなかったときだけ、cwd 単位（タグ無し）の
	-- セッションへ落ちる。タグ導入前に保存された古いセッションや、herdr の外で
	-- 作ったセッションを拾うため。タグ付けの目的は複数ペインの上書き防止なので、
	-- 読み込み側まで厳格にする必要はない。
	--
	-- 復元後の保存は従来どおりタグ付きの名前で行われるため、1回開けば自動で
	-- タグ付きへ移行する。
	--
	-- 同じ cwd を複数ペインで開いている場合、フォールバックが走る初回だけ
	-- 両ペインが同じ内容で開く。以後はペインごとに分かれる。
	no_restore_cmds = {
		function()
			-- no_restore は「タグ付きが無かった」以外の理由でも発火する。
			-- ここで対象を絞らないと、auto-session が意図して復元を止めた場面まで
			-- 復元してしまう。
			--
			-- とくに `nvim somefile` は args_allow_files_auto_save = false により
			-- 復元対象外だが no_restore は発火するため、フォールバックが走ると
			-- 開こうとしたファイルがセッションの内容で置き換わる。
			-- 引数なしの素の起動（＝復元を期待している起動）だけを対象にする。
			-- 単一ディレクトリ引数（`nvim .`）は auto-session 自身が cwd 単位の
			-- セッションを読むので、こちらで拾う必要はない。
			if launch_argc > 0 then
				return
			end

			-- headless（daily-update の Lazy/Mason 更新など）と pager モード
			-- （`git diff | nvim -`）も auto-session は復元対象外にしている。
			-- どちらも人が続けて編集する起動ではないので、追随して何もしない。
			if is_headless() or vim.g.in_pager_mode then
				return
			end

			local pane = vim.env.HERDR_PANE_ID
			if not pane or pane == "" then
				-- herdr の外の nvim は元からタグ無しで、落ちる先が同じなので何もしない。
				return
			end

			local auto_session = require("auto-session")
			local lib = require("auto-session.lib")
			local config = require("auto-session.config")

			-- セッション名の作り方を auto-session 側と揃える。
			local cwd = vim.fn.getcwd(-1, -1)
			if config.resolve_symlinks then
				cwd = lib.remove_trailing_separator(vim.fn.resolve(cwd))
			end

			local path = auto_session.get_root_dir() .. lib.escape_session_name(cwd) .. ".vim"
			if vim.fn.filereadable(path) == 0 then
				return
			end

			-- restore_session(name) ではなくファイル指定で読む。前者は「手動命名
			-- セッション」と判定されて manually_named_session が立ち、以後の保存まで
			-- タグ無しの名前に固定されてしまう。
			auto_session.restore_session_file(path)
		end,
	},
	-- tmux kill-server等でSIGHUP/SIGTERM受信中のセッション保存をスキップ
	pre_save_cmds = {
		function()
			if vim.v.dying > 0 then
				return false
			end
		end,
	},
})

-- 稼働中の定期保存。
--
-- auto-session の保存契機は VimLeavePre だけで、かつ上の v:dying ガードにより
-- シグナル終了時は保存しない。herdr のサーバー再起動は各ペインの nvim を
-- SIGTERM/SIGHUP で落とすため、これだけだと `he` がペインを復元しても
-- 「最後に :q で終了したときの状態」までしか戻らない。
--
-- 終了処理中ではなく操作が落ち着いたタイミングで書くので、v:dying ガードを外す場合と違い
-- 書き込み中断によるセッションファイル破損のリスクは増えない。SIGKILL や WSL の強制終了も
-- カバーできる。
local save_timer = vim.uv.new_timer()
local SAVE_DEBOUNCE_MS = 5000

local function schedule_auto_save()
	save_timer:stop()
	save_timer:start(
		SAVE_DEBOUNCE_MS,
		0,
		vim.schedule_wrap(function()
			if vim.v.dying > 0 then
				return
			end
			-- 復元前や素の起動直後に空セッションで上書きしないよう、
			-- 名前付きの listed バッファが1つも無い間は保存しない。
			local has_named_buffer = false
			for _, buf in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
				if buf.name ~= "" then
					has_named_buffer = true
					break
				end
			end
			if not has_named_buffer then
				return
			end
			-- suppressed_dirs や args_allow_files_auto_save 等の判定は
			-- auto_save_session() 側が持っているため、ここでは重複して持たない。
			require("auto-session").auto_save_session()
		end)
	)
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "WinEnter", "FocusLost" }, {
	group = vim.api.nvim_create_augroup("my_auto_session_periodic_save", {}),
	callback = schedule_auto_save,
})
