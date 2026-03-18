---@type vim.lsp.Config
return {
	-- デフォルトのroot_markersには ".git" が含まれるため、
	-- monorepoではrepo root全体がworkspaceになりメモリを大量消費する。
	-- ".git" を除外し、最寄りのtsconfig.json/package.jsonでworkspaceを区切る。
	root_markers = { "tsconfig.json", "jsconfig.json", "package.json" },
}
