-- 起動理由から「auto-session にセッションを復元させてよいか」を決める。
--
-- nvim 0.12.5 の `:restart`（bang なし）と `ZR` は、nvim 自身が mksession で
-- セッションを保存し、再起動後、UI アタッチ後にそれを source する
-- （`:h :restart` の手順1と4。実装は $VIMRUNTIME/lua/vim/_core/server.lua）。
--
-- auto-session は v:startreason を見ないため、そのままだと VimEnter の auto_restore と
-- nvim 本体の source が両方走る。sessionoptions に buffers を含むのでバッファリストが
-- 2セッション分の和になり、auto-session.lua の定期保存がその和をプロジェクトの
-- セッションファイルへ焼き付ける。
--
-- `:restart!` は「セッションを復元しない」という明示指定なので、ここで auto-session が
-- 復元すると指定が潰れる。したがって restart 由来の起動は bang の有無を問わず止める。
local M = {}

--- @param reason string|nil `v:startreason`。0.12.5 より前は nil
--- @return boolean
function M.should_auto_restore(reason)
	-- 未知の値は「復元しない」側ではなく従来の挙動へ倒す。nvim が起動理由を
	-- 増やしたときに、復元されないほうが事故として気づきにくいため。
	return reason ~= "restart" and reason ~= "restart!"
end

--- @return boolean
function M.is_normal_start()
	return M.should_auto_restore(vim.v.startreason)
end

return M
