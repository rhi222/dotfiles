require("yazi").setup({
	open_for_directories = true,
	floating_window_scaling_factor = 0.6,
	yazi_floating_window_border = "rounded",
	use_ya_as_event_reader = true,
	highlight_hovered_buffers_in_same_directory = true,
	clipboard_register = "+",
	hooks = {
		-- yazi.nvim 13.1.5 では terminal job 終了から buffer wipe 完了までの間に
		-- VimResized autocmd が dead channel に jobresize して E900 を投げる race
		-- がある。TermClose で当該 buffer の VimResized autocmd を即時剥がして潰す。
		yazi_opened = function(_, content_buffer, _)
			vim.api.nvim_create_autocmd("TermClose", {
				buffer = content_buffer,
				once = true,
				callback = function()
					if vim.api.nvim_buf_is_valid(content_buffer) then
						vim.api.nvim_clear_autocmds({
							event = "VimResized",
							buffer = content_buffer,
						})
					end
				end,
			})
		end,
	},
	integrations = {
		grep_in_directory = function(directory)
			require("fzf-lua").live_grep({ cwd = directory })
		end,
		grep_in_selected_files = function(selected_files)
			require("fzf-lua").live_grep({ search_paths = selected_files })
		end,
	},
})
