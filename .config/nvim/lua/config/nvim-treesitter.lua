-- https://github.com/nvim-treesitter/nvim-treesitter
require'nvim-treesitter.configs'.setup{
	ensure_installed = {
		'javascript',
		'lua',
		'python',
		'tsx',
		'typescript',
		'vim',
		'vimdoc',
		'xml'
	},
	highlight = {
		enable = true
	}
}
