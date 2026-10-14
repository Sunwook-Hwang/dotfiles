local policy = require("buffer_policy")
local oil = require("oil")
local project = require("project")

local function editor_window(preferred)
	if
		preferred
		and vim.api.nvim_win_is_valid(preferred)
		and vim.api.nvim_win_get_tabpage(preferred) == vim.api.nvim_get_current_tabpage()
		and (policy.is_editor(preferred) or vim.bo[vim.api.nvim_win_get_buf(preferred)].filetype == "alpha")
	then
		return preferred
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if policy.is_editor(win) then
			return win
		end
	end
end

local function close_explorer()
	if not vim.w.pack_oil_editor then
		return oil.close()
	end
	local editor = editor_window(vim.w.pack_oil_editor)
	if #vim.api.nvim_tabpage_list_wins(0) == 1 then
		oil.close()
		vim.w.pack_oil_editor = nil
		vim.wo.winfixwidth = false
	else
		vim.api.nvim_win_close(0, false)
		if editor then
			vim.api.nvim_set_current_win(editor)
		end
	end
end

local function select_entry(opts)
	local sidebar = vim.api.nvim_get_current_win()
	local directory_buf = vim.api.nvim_get_current_buf()
	if not vim.w.pack_oil_editor then
		return oil.select(opts)
	end
	oil.select({
		handle_buffer_callback = function(buf)
			if
				not vim.api.nvim_win_is_valid(sidebar)
				or vim.api.nvim_win_get_buf(sidebar) ~= directory_buf
				or not vim.w[sidebar].pack_oil_editor
			then
				return
			end
			vim.api.nvim_set_current_win(sidebar)
			if oil.get_current_dir(buf) then
				vim.cmd.buffer(buf)
				return
			end
			local editor = editor_window(vim.w[sidebar].pack_oil_editor)
			if not editor then
				vim.cmd({ cmd = "sbuffer", args = { buf }, mods = { vertical = true, split = "botright" } })
				editor = vim.api.nvim_get_current_win()
			end
			vim.api.nvim_set_current_win(editor)
			if opts and opts.tab then
				vim.cmd("tab sbuffer " .. buf)
			elseif opts and (opts.vertical or opts.horizontal) then
				vim.cmd({ cmd = "sbuffer", args = { buf }, mods = { vertical = opts.vertical, split = "belowright" } })
			else
				vim.cmd.buffer(buf)
			end
			if not (opts and opts.tab) then
				vim.w[sidebar].pack_oil_editor = vim.api.nvim_get_current_win()
			end
		end,
	})
end

oil.setup({
	columns = {}, -- File names only; no icon provider required.
	win_options = { number = false, relativenumber = false, statuscolumn = "", signcolumn = "yes" },
	view_options = { show_hidden = true }, -- Git-ignored files are visible too.
	watch_for_changes = false,
	use_default_keymaps = false, -- Match FLASH where Oil provides the same action.
	keymaps = {
		["<CR>"] = { callback = select_entry, desc = "Open entry; files use the editing window", mode = "n" },
		["<C-c>"] = { callback = close_explorer, desc = "Close explorer", mode = "n" },
		-- Window navigation and save keys inherit the profile's global mappings.
		["<C-t>"] = {
			callback = function()
				return require("terminal").toggle()
			end,
			desc = "Toggle bottom terminal",
			mode = { "n", "i" },
		},
		["<localleader>v"] = {
			callback = select_entry,
			opts = { vertical = true },
			desc = "Open file in vertical split",
			mode = "n",
		},
		["<localleader>s"] = {
			callback = select_entry,
			opts = { horizontal = true },
			desc = "Open file in horizontal split",
			mode = "n",
		},
		["<localleader>t"] = {
			callback = select_entry,
			opts = { tab = true },
			desc = "Open file in new tab",
			mode = "n",
		},
		["-"] = { "actions.parent", mode = "n" },
		["<localleader>w"] = { "actions.open_cwd", mode = "n" },
		["<localleader>p"] = { "actions.preview", mode = "n" },
		["<localleader>d"] = { "actions.cd", mode = "n" },
		["<localleader>D"] = { "actions.cd", opts = { scope = "tab" }, mode = "n" },
		["gr"] = {
			callback = function()
				require("oil-git.git").invalidate_cache()
				require("oil.actions").refresh.callback()
			end,
			desc = "Refresh directory and Git status",
			mode = "n",
		},
		["g."] = { "actions.toggle_hidden", mode = "n" },
		["gs"] = { "actions.change_sort", mode = "n" },
		["gx"] = { "actions.open_external", mode = "n" },
		["g?"] = { "actions.show_help", mode = "n" },
	},
})

local git_symbols = {
	added = "+",
	modified = "M",
	renamed = "R",
	deleted = "D",
	copied = "C",
	conflict = "U",
	untracked = "?",
	ignored = "!",
}
require("oil-git").setup({
	symbol_position = "signcolumn",
	can_use_signcolumn = function()
		return true -- Oil reserves a fixed column, including for clean directories.
	end,
	show_file_highlights = false,
	show_directory_highlights = false,
	show_ignored_files = true,
	show_ignored_directories = true,
	ignore_gitsigns_update = true, -- Do not refresh Oil for every source-buffer edit.
	symbols = { file = git_symbols, directory = git_symbols },
})

-- -------------------------------------
-- File explorer: use the same package / standard-library / project boundaries as nopack.
-- -------------------------------------
do
	vim.api.nvim_create_autocmd("BufEnter", {
		group = vim.api.nvim_create_augroup("pack-project-root", { clear = true }),
		callback = function(args)
			local file = vim.api.nvim_buf_get_name(args.buf)
			if not policy.is_editor(0) or file == "" then
				return
			end
			local dir = vim.fs.dirname(file)
			local cached = project.for_dir(dir)
			if not cached.recognized then
				return
			end
			local root = cached.root
			if vim.fn.getcwd() ~= root then
				vim.cmd.lcd(vim.fn.fnameescape(root))
			end
		end,
	})
	vim.api.nvim_create_user_command("PackRefresh", function()
		vim.api.nvim_exec_autocmds("User", { pattern = "PackRefresh", modeline = false })
		vim.api.nvim_exec_autocmds("BufEnter", { group = "pack-project-root", buffer = 0, modeline = false })
		vim.cmd("redrawstatus")
	end, { desc = "Refresh project root and formatter availability" })
	vim.keymap.set("n", "<leader>e", function()
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.w[win].pack_oil_editor and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "oil" then
				vim.api.nvim_set_current_win(win)
				close_explorer()
				return
			end
		end
		local dir
		local wins = { vim.api.nvim_get_current_win() }
		vim.list_extend(wins, vim.api.nvim_tabpage_list_wins(0))
		for _, win in ipairs(wins) do
			local buf = vim.api.nvim_win_get_buf(win)
			local name = vim.api.nvim_buf_get_name(buf)
			if policy.is_editor(win) and name ~= "" then
				dir = vim.fs.dirname(name)
				vim.api.nvim_set_current_win(win)
				break
			end
		end
		local editor = vim.api.nvim_get_current_win()
		local placeholder = vim.api.nvim_create_buf(false, true)
		vim.bo[placeholder].bufhidden = "wipe"
		vim.api.nvim_open_win(placeholder, true, { split = "left", win = -1, width = 40 })
		vim.w.pack_oil_editor = editor
		vim.wo.winfixwidth = true
		oil.open(project.for_dir(dir or vim.fn.getcwd()).root)
	end, { desc = "Toggle file explorer" })
end
