local shared = require("state")

-- =========================================
-- ============ SPLIT TERMINAL ===========
-- =========================================
-- Ctrl-t: reopen the same shell job in a bottom split matching the size of <leader>gg.
-- <leader>TT: stop the existing shell and start a new shell in the editor window's :pwd.
-- Exclude terminal buffers from ordinary buffer cycling; clean up only exited shells.
local terminal
local terminal_zoom
local function restore_terminal_zoom()
	if not terminal_zoom then
		return
	end
	local zoom = terminal_zoom
	terminal_zoom = nil
	local target = vim.api.nvim_win_is_valid(zoom.focus) and zoom.focus or zoom.source
	if vim.api.nvim_win_is_valid(target) then
		vim.api.nvim_set_current_win(target)
		if vim.api.nvim_win_is_valid(zoom.win) then
			vim.api.nvim_win_close(zoom.win, true)
		end
	end
end

local function terminal_running(buf)
	local job = vim.bo[buf].channel
	if type(job) ~= "number" or job <= 0 then
		return false
	end
	local ok, status = pcall(vim.fn.jobwait, { job }, 0)
	return ok and status[1] == -1
end
local function toggle_terminal(restart)
	restore_terminal_zoom()
	if restart then
		shared.focus_editor()
	end
	local cwd = vim.fn.getcwd()
	local reuse_win
	if
		terminal
		and vim.api.nvim_buf_is_valid(terminal)
		and vim.bo[terminal].buftype == "terminal"
		and (restart or not terminal_running(terminal))
	then
		local win = vim.fn.bufwinid(terminal)
		if win ~= -1 then
			-- Replace the buffer first so deleting the old job preserves this split.
			local buf = vim.api.nvim_create_buf(false, false)
			vim.bo[buf].bufhidden = "hide"
			vim.api.nvim_win_set_buf(win, buf)
			reuse_win = win
		end
		vim.api.nvim_buf_delete(terminal, { force = true })
		terminal = nil
	end
	if terminal and vim.api.nvim_buf_is_valid(terminal) then
		local win = vim.fn.bufwinid(terminal)
		if win ~= -1 then
			vim.cmd("stopinsert")
			vim.api.nvim_win_call(win, function()
				-- Hide the shell even when its split is the tab's last window.
				vim.cmd(vim.fn.winnr("$") > 1 and "hide" or "enew")
			end)
			return
		end
	end
	if terminal and vim.api.nvim_buf_is_valid(terminal) then
		vim.cmd("botright sbuffer " .. terminal)
	else
		if reuse_win then
			vim.api.nvim_set_current_win(reuse_win)
		else
			vim.cmd("botright new")
		end
		terminal = vim.api.nvim_get_current_buf()
		vim.bo.bufhidden = "hide"
		vim.bo.buflisted = false
		vim.fn.jobstart(vim.o.shell, { term = true, cwd = cwd })
	end
	vim.cmd("startinsert")
end
local function toggle_terminal_zoom()
	vim.cmd("stopinsert")
	if terminal_zoom and vim.api.nvim_win_is_valid(terminal_zoom.win) then
		restore_terminal_zoom()
	else
		local focus = vim.api.nvim_get_current_win()
		if not terminal or not vim.api.nvim_buf_is_valid(terminal) or not terminal_running(terminal) then
			toggle_terminal()
		elseif vim.fn.bufwinid(terminal) == -1 then
			toggle_terminal()
		end
		local source = vim.fn.bufwinid(terminal)
		if source == -1 then
			return
		end
		vim.api.nvim_set_current_win(source)
		vim.cmd("tab split")
		terminal_zoom = { source = source, focus = focus, win = vim.api.nvim_get_current_win() }
	end
	if vim.bo.buftype == "terminal" then
		vim.cmd("startinsert")
	end
end

local zoom_key = "<Plug>(flash-terminal-zoom)"
vim.keymap.set("n", zoom_key, toggle_terminal_zoom, { silent = true })
for _, keys in ipairs({ "<C-\\>\\", "<C-\\><C-\\>" }) do
	shared.map("n", keys, toggle_terminal_zoom, "Toggle terminal fullscreen")
	shared.map({ "i", "t" }, keys, "<C-\\><C-n>" .. zoom_key, "Toggle terminal fullscreen")
	shared.map("x", keys, "<Esc>" .. zoom_key, "Toggle terminal fullscreen")
end
shared.map({ "n", "t" }, "<C-t>", toggle_terminal, "Toggle bottom terminal")
shared.map("n", "<leader>TT", function()
	toggle_terminal(true)
end, "Restart terminal in editor directory")
