-- https://github.com/mistweaverco/kulala.nvim
require("kulala").setup({
	-- LSP は既定で javascript / typescript / lua にも attach する。
	-- *.http.js のような外部スクリプトを使っていないので http だけに絞る
	lsp = { filetypes = { "http" } },
	-- response buffer でも V を行単位 Visual mode として使えるようにする。
	-- Kulala 既定の verbose 表示は gV へ移す。
	kulala_keymaps = {
		["Show verbose"] = {
			"gV",
			function()
				require("kulala.ui").show_verbose()
			end,
		},
	},
})

-- SSL 検証をスキップしたい検証環境では、その repo の http-client.env.json に置く:
--   { "$kulalaShared": { "$kulalaDefaultCurlOptions": ["--insecure"] } }
-- rest.nvim ではグローバルに検証を切っていたため「本番系エンドポイントには使うな」という
-- NOTE が必要だったが、kulala v6 は nvim 設定側にグローバル指定を持たないので、
-- その危険が構造的に無くなる。リクエスト単位なら `# @kulala-curl--insecure`。
