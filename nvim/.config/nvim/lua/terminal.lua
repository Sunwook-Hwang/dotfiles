local shared = require("state")

-- =========================================
-- ============ SPLIT TERMINAL ===========
-- =========================================
-- Ctrl-t: reopen the same shell job in a bottom split matching the size of <leader>gg.
-- <leader>TT: stop the existing shell and start a new shell in the editor window's :pwd.
-- Exclude terminal buffers from ordinary buffer cycling; clean up only exited shells.
local terminal
local function terminal_running(buf)
	local job = vim.bo[buf].channel
	if type(job) ~= "number" or job <= 0 then
		return false
	end
	local ok, status = pcall(vim.fn.jobwait, { job }, 0)
	return ok and status[1] == -1
end
local function toggle_terminal(restart)
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
shared.map({ "n", "t" }, "<C-t>", toggle_terminal, "Toggle bottom terminal")
shared.map("n", "<leader>TT", function()
	toggle_terminal(true)
end, "Restart terminal in editor directory")
