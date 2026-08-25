-- 起動時の引数の数。setup() より前に取っておく。
-- auto-session も同じ理由（NvimTree 等が引数を書き換える前に見る必要がある）で
-- setup() の中で argv を控えており、ここは同じタイミングになる。
local launch_argc = #vim.fn.argv()

-- `:restart` / `ZR` 由来の起動では nvim 本体がセッションを復元するため、
-- auto-session 側の復元を止めて二重復元を防ぐ。理由の詳細は session-start.lua。
local is_normal_start = require("my.plugins.tools.session-start").is_normal_start()
local restore_session_tag = vim.env.HERDR_RESTORE_SESSION_TAG

local function clear_restore_session_tag()
	restore_session_tag = nil
	vim.env.HERDR_RESTORE_SESSION_TAG = nil
end

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

-- 全プロジェクトで共有するスクラッチパッド（my/commands/temporary-work.lua の
-- :Inbox と :Temp が開くもの）。プロジェクト固有のセッションに載せない。
--
-- 載せると、herdr 復元時に同じ cwd の全ペインが同じスクラッチパッドを画面に出す。
-- タグ付きセッションが無いペインは cwd 単位セッションへフォールバックするため
-- （下の no_restore_cmds）、cwd 単位セッションの表示バッファがスクラッチパッドだと
-- そのコピーが全ペインへ広がり、さらに定期保存で各ペインのセッションに焼き付く。
local SCRATCHPAD_FILES = {
	vim.fn.expand("~/.inbox.md"),
}
local SCRATCHPAD_DIRS = {
	vim.fn.expand("~/.nvim_tmp") .. "/",
}

local function is_scratchpad(name)
	if name == "" then
		return false
	end
	local path = vim.fn.fnamemodify(name, ":p")
	for _, file in ipairs(SCRATCHPAD_FILES) do
		if path == file then
			return true
		end
	end
	for _, dir in ipairs(SCRATCHPAD_DIRS) do
		if path:sub(1, #dir) == dir then
			return true
		end
	end
	return false
end

-- ウィンドウに出ているかどうかで判定する。バッファ一覧に居るだけなら
-- 復元しても画面には出ないので放っておく。
-- nvim_list_wins() は全タブページのウィンドウを返す。
local function scratchpad_is_visible()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if is_scratchpad(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))) then
			return true
		end
	end
	return false
end

-- auto-session は保存前に checkhealth buffer を削除する。終了時の保存では問題ないが、
-- 稼働中の定期保存で同じ処理を呼ぶと :checkhealth の結果が5秒後に勝手に閉じる。
-- 一時画面を session に含めず、かつ表示自体も壊さないため、見えている間だけ定期保存を見送る。
local function transient_view_is_visible()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].filetype == "checkhealth" then
			return true
		end
	end
	return false
end

require("auto-session").setup({
	enabled = true,
	auto_save = true,
	auto_restore = is_normal_start,
	show_auto_restore_notif = true,
	-- headlessテストではLazy画面の終了順が通常起動と異なり、復元待ちのままwqaすると
	-- セッションが保存されない。テスト時だけ待機を外し、VimEnterを直接検査する。
	lazy_support = not vim.env.AUTOSESSION_UNIT_TESTING,
	-- XDG_DATA_HOME を変えると lazy.nvim の plugin root まで変わるため、実 nvim 設定を
	-- 使うテストは session の保存先だけを一時ディレクトリへ隔離する。
	root_dir = vim.env.MY_AUTOSESSION_ROOT_DIR or (vim.fn.stdpath("data") .. "/sessions/"),
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
		if restore_session_tag and restore_session_tag ~= "" then
			return restore_session_tag
		end
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
			-- pane move後の旧tagは最初の検索にだけ使う。見つからなかった場合の
			-- cwd fallbackと、その後の保存は現在paneのtagへ戻す。
			clear_restore_session_tag()
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

			-- auto_restore = false でも auto-session は no_restore を発火するため、
			-- ここも塞がないと restart 由来の起動でフォールバック側から二重復元が復活する。
			if not is_normal_start then
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
	post_restore_cmds = {
		clear_restore_session_tag,
	},
	-- tmux kill-server等でSIGHUP/SIGTERM受信中のセッション保存をスキップ
	pre_save_cmds = {
		function()
			if vim.v.dying > 0 then
				return false
			end
			-- スクラッチパッドが画面に出ている間は保存を見送り、直前に保存された
			-- 状態を残す。バッファを消すのではなく保存を止めるのは、定期保存が
			-- 編集中に何度も走るため。消す実装だと編集中のバッファを閉じてしまう。
			if scratchpad_is_visible() then
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
-- テストから短縮できるようにする。テスト側はこのデバウンスが切れるのを待つしかなく、
-- 既定の 5000ms のままだと固定 sleep が積み上がってスイート全体が50秒伸びる。
-- 本番の既定値は 5000 のまま（test-nvim-session-autosave.sh が既定値を固定している）。
local SAVE_DEBOUNCE_MS = tonumber(vim.env.MY_AUTOSESSION_SAVE_DEBOUNCE_MS) or 5000

local function schedule_auto_save()
	save_timer:stop()
	save_timer:start(
		SAVE_DEBOUNCE_MS,
		0,
		vim.schedule_wrap(function()
			if vim.v.dying > 0 then
				return
			end
			if transient_view_is_visible() then
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
			local saved = require("auto-session").auto_save_session()
			if saved then
				local ok, registry = pcall(require, "my.settings.herdr-registry")
				if ok then
					registry.session_saved()
				end
			end
		end)
	)
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "WinEnter", "FocusLost" }, {
	group = vim.api.nvim_create_augroup("my_auto_session_periodic_save", {}),
	callback = schedule_auto_save,
})
