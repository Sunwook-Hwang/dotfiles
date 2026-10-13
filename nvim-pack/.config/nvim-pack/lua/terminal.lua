local Snacks = require("snacks")
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

local function open_terminal()
	terminal_cwd = terminal_cwd or vim.fn.getcwd()
	local shell = Snacks.terminal.open(nil, { cwd = terminal_cwd, count = 1, auto_close = false })
	terminal = shell
	-- Keep the exit handler alive while Snacks hides its window and removes window events.
	vim.api.nvim_create_autocmd("TermClose", {
		buffer = shell.buf,
		once = true,
		callback = function()
			local status = vim.v.event.status
			vim.schedule(function()
				if terminal ~= shell or vim.v.exiting ~= vim.NIL then
					return
				end
				if status ~= 0 and not restart_cwd then
					Snacks.notify.error("Terminal exited with code " .. status)
					return
				end
				restore_zoom()
				shell:close()
				terminal = nil
				if restart_cwd then
					terminal_cwd, restart_cwd = restart_cwd, nil
					open_terminal()
				end
			end)
		end,
	})
	return shell
end

local function get_terminal()
	if terminal and terminal:buf_valid() then
		local job = vim.bo[terminal.buf].channel
		if job > 0 and vim.fn.jobwait({ job }, 0)[1] == -1 then
			return terminal, false
		end
		terminal:close()
	end
	return open_terminal(), true
end
local function toggle_bottom_terminal()
	restore_zoom()
	if restart_cwd then
		return
	end
	local shell, created = get_terminal()
	if not created then
		shell:toggle()
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
	if terminal and terminal:buf_valid() then
		local job = vim.bo[terminal.buf].channel
		if job > 0 and vim.fn.jobwait({ job }, 0)[1] == -1 then
			restart_cwd = cwd
			terminal:hide()
			vim.fn.jobstop(job)
			return
		end
		terminal:close()
	end
	terminal_cwd = cwd
	open_terminal()
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
		local shell = get_terminal()
		shell:show():focus()
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

vim.keymap.set("n", "<leader>gg", function()
	if vim.fn.executable("lazygit") == 1 then
		Snacks.lazygit()
	else
		Snacks.picker.git_status()
	end
end, { desc = "Open lazygit or Git status" })

return { toggle = toggle_bottom_terminal, restore_zoom = restore_zoom }
