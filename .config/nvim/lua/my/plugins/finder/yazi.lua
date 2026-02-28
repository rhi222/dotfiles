require("yazi").setup({
	open_for_directories = true,
	floating_window_scaling_factor = 0.6,
	yazi_floating_window_border = "rounded",
	use_ya_as_event_reader = true,
	highlight_hovered_buffers_in_same_directory = true,
	integrations = {
		grep_in_directory = function(directory)
			require("fzf-lua").live_grep({ cwd = directory })
		end,
		grep_in_selected_files = function(selected_files)
			require("fzf-lua").live_grep({ search_paths = selected_files })
		end,
	},
})
