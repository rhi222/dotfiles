---@type vim.lsp.Config
return {
	-- デフォルトのroot_markersには ".git" が含まれるため、
	-- monorepoではrepo root全体がworkspaceになりメモリを大量消費する。
	-- ".git" を除外し、最寄りのtsconfig.json/package.jsonでworkspaceを区切る。
	root_markers = { "tsconfig.json", "jsconfig.json", "package.json" },
	init_options = {
		-- tsserverのヒープ上限(MB)。未指定だとNodeのデフォルト(4GB前後)まで
		-- 際限なく成長しうるため、複数プロジェクト同時起動時のメモリ暴走を防ぐ。
		-- 超過時はtsserverのみクラッシュする（:LspRestart で復帰）。
		maxTsServerMemory = 3072,
		-- @typesの自動取得を無効化。tsconfigで型が揃っているプロジェクトでは実害なし。
		disableAutomaticTypingAcquisition = true,
		tsserver = {
			-- syntax専用サーバー(--serverMode partialSemantic, 約150MB/プロジェクト)を
			-- 起動せず1プロセスに統合する。重い解析中はハイライト系の応答が遅れうる。
			useSyntaxServer = "never",
		},
	},
}
