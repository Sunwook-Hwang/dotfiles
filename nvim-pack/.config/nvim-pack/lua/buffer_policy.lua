-- Shared eligibility for automatic editing features and code analysis.
local M = {}

function M.is_source(buf)
	buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
	return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == ""
end

function M.allows(buf)
	buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
	return vim.api.nvim_buf_is_loaded(buf) and M.is_source(buf) and not vim.b[buf].large_file
end

-- Editing targets exclude utility, floating and preview windows.
function M.is_editor(win)
	win = (win == nil or win == 0) and vim.api.nvim_get_current_win() or win
	return vim.api.nvim_win_is_valid(win)
		and M.is_source(vim.api.nvim_win_get_buf(win))
		and vim.api.nvim_win_get_config(win).relative == ""
		and not vim.wo[win].previewwindow
end

function M.guard(callback)
	return function(...)
		if M.allows(0) then
			return callback(...)
		end
	end
end

function M.restrict(buf)
	if vim.b[buf].large_file then
		return
	end
	vim.b[buf].large_file = true
	vim.api.nvim_exec_autocmds("User", { pattern = "PackBufferRestricted", data = { buf = buf }, modeline = false })
end

return M
