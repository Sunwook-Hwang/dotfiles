local policy = require("buffer_policy")
local terminal, terminal_cwd, zoom, restart_cwd
local function restore_zoom()
	if not zoom then
		return
	end
	local saved = zoom
	zoom = nil
	local target = vim.api.nvim_win_is_valid(saved.focus) and saved.focus or saved.source
	if vim.api.nvim_win_is_valid(target) then
		vim.api.nvim_set_current_win(target)
		if vim.api.nvim_win_is_valid(saved.win) then
			vim.api.nvim_win_close(saved.win, true)
		end
	end
end
local function running(buf)
	return buf
		and vim.api.nvim_buf_is_valid(buf)
		and vim.bo[buf].channel > 0
		and vim.fn.jobwait({ vim.bo[buf].channel }, 0)[1] == -1
end
local function hide(buf)
	local win = buf and vim.fn.bufwinid(buf) or -1
	if win ~= -1 then
		vim.cmd("stopinsert")
		vim.api.nvim_win_call(win, function()
			vim.cmd(vim.fn.winnr("$") > 1 and "hide" or "enew")
		end)
	end
end
local function remove(buf)
	if buf and vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
local function terminal_window(buf, config)
	local win = vim.api.nvim_open_win(buf, true, config)
	for option, value in pairs({
		number = false,
		relativenumber = false,
		signcolumn = "no",
		statuscolumn = "",
		cursorline = false,
		cursorcolumn = false,
	}) do
		vim.api.nvim_set_option_value(option, value, { win = win, scope = "local" })
	end
	return win
end
local open_terminal
open_terminal = function()
	terminal_cwd = terminal_cwd or vim.fn.getcwd()
	terminal = vim.api.nvim_create_buf(false, true)
	vim.bo[terminal].bufhidden = "hide"
	terminal_window(terminal, { split = "below", win = -1, height = math.max(1, math.floor(vim.o.lines * 0.3)) })
	local buf = terminal
	local job = vim.fn.jobstart(vim.o.shell, {
		term = true,
		cwd = terminal_cwd,
		on_exit = function(_, status)
			vim.schedule(function()
				if vim.v.exiting ~= vim.NIL then
					return
				end
				if terminal ~= buf then
					remove(buf)
					return
				end
				if status ~= 0 and not restart_cwd then
					vim.notify("Terminal exited with code " .. status, vim.log.levels.ERROR)
					return
				end
				restore_zoom()
				terminal = nil
				remove(buf)
				if restart_cwd then
					terminal_cwd, restart_cwd = restart_cwd, nil
					open_terminal()
				end
			end)
		end,
	})
	if job <= 0 then
		terminal = nil
		remove(buf)
		vim.notify("Could not start terminal shell", vim.log.levels.ERROR)
		return
	end
	vim.cmd("startinsert")
	return buf
end
local function show_terminal()
	if not running(terminal) then
		remove(terminal)
		return open_terminal()
	end
	local win = vim.fn.bufwinid(terminal)
	if win == -1 then
		terminal_window(terminal, { split = "below", win = -1, height = math.max(1, math.floor(vim.o.lines * 0.3)) })
	else
		vim.api.nvim_set_current_win(win)
	end
	vim.cmd("startinsert")
	return terminal
end
local function toggle_bottom_terminal()
	restore_zoom()
	if restart_cwd then
		return
	end
	if running(terminal) and vim.fn.bufwinid(terminal) ~= -1 then
		hide(terminal)
	else
		show_terminal()
	end
end
local function restart_terminal()
	restore_zoom()
	if not policy.is_editor(0) then
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if policy.is_editor(win) then
				vim.api.nvim_set_current_win(win)
				break
			end
		end
	end
	local cwd = vim.fn.getcwd()
	if restart_cwd then
		restart_cwd = cwd
		return
	end
	if running(terminal) then
		restart_cwd = cwd
		hide(terminal)
		-- Retire the old buffer only after the PTY exit callback has run.
		vim.fn.jobstop(vim.bo[terminal].channel)
	else
		remove(terminal)
		terminal_cwd = cwd
		open_terminal()
	end
end
local function toggle_fullscreen()
	vim.cmd("stopinsert")
	if restart_cwd then
		return
	end
	if zoom and vim.api.nvim_win_is_valid(zoom.win) then
		restore_zoom()
	else
		local focus = vim.api.nvim_get_current_win()
		if not show_terminal() then
			return
		end
		local source = vim.api.nvim_get_current_win()
		vim.cmd("tab split")
		zoom = { focus = focus, source = source, win = vim.api.nvim_get_current_win() }
	end
	if vim.bo.buftype == "terminal" then
		vim.cmd("startinsert")
	end
end
vim.keymap.set({ "n", "t" }, "<C-t>", toggle_bottom_terminal, { desc = "Toggle bottom terminal" })
vim.keymap.set("n", "<leader>TT", restart_terminal, { desc = "Restart terminal in editor directory" })
local zoom_key = "<Plug>(pack-terminal-zoom)"
vim.keymap.set("n", zoom_key, toggle_fullscreen, { silent = true })
for _, keys in ipairs({ "<C-\\>\\", "<C-\\><C-\\>" }) do
	vim.keymap.set("n", keys, toggle_fullscreen, { desc = "Toggle terminal fullscreen" })
	vim.keymap.set({ "i", "t" }, keys, "<C-\\><C-n>" .. zoom_key, { desc = "Toggle terminal fullscreen" })
	vim.keymap.set("x", keys, "<Esc>" .. zoom_key, { desc = "Toggle terminal fullscreen" })
end

local lazygit
vim.keymap.set("n", "<leader>gg", function()
	if vim.fn.executable("lazygit") == 0 then
		return require("pickers").open("git_status")
	end
	if running(lazygit) and vim.fn.bufwinid(lazygit) ~= -1 then
		hide(lazygit)
		return
	end
	local width, height =
		math.max(1, math.floor(vim.o.columns * 0.9)), math.max(1, math.floor((vim.o.lines - vim.o.cmdheight) * 0.9))
	local reuse = running(lazygit)
	if not reuse then
		remove(lazygit)
		lazygit = vim.api.nvim_create_buf(false, true)
	end
	vim.bo[lazygit].bufhidden = "hide"
	local win = terminal_window(lazygit, {
		relative = "editor",
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
	})
	vim.wo[win].winhighlight = "Normal:Normal,NormalFloat:Normal"
	if not reuse then
		local buf = lazygit
		local job = vim.fn.jobstart({ "lazygit" }, {
			term = true,
			on_exit = function()
				vim.schedule(function()
					if lazygit == buf then
						lazygit = nil
					end
					remove(buf)
				end)
			end,
		})
		if job <= 0 then
			lazygit = nil
			remove(buf)
			return
		end
	end
	vim.cmd("startinsert")
end, { desc = "Open lazygit or Git status" })

return { toggle = toggle_bottom_terminal, restore_zoom = restore_zoom }
