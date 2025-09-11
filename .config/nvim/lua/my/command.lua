-- -------------------- user command {{{
-- https://github.com/willelz/nvim-lua-guide-ja/blob/master/README.ja.md#%E3%83%A6%E3%83%BC%E3%82%B6%E3%83%BC%E3%82%B3%E3%83%9E%E3%83%B3%E3%83%89%E3%82%92%E5%AE%9A%E7%BE%A9%E3%81%99%E3%82%8B

return {
	require("my/commands/open-git"),
	require("my/commands/temporary-work"),
	require("my/commands/cd"),
	require("my/commands/cp-current-file-path"),
	require("my/commands/cp-to-host"),
}
-- }}} -------------------------------
