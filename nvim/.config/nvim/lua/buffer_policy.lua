-- Shared eligibility for automatic editing features and code analysis.
local M = {}

-- Picker buffer lifecycle events do not signal file changes; global notifications still do.
function M.is_picker_event(args)
	return args.event ~= "FocusGained"
		and args.event ~= "ShellCmdPost"
		and vim.api.nvim_buf_is_valid(args.buf)
		and vim.b[args.buf].nopack_picker_role ~= nil
end

function M.is_source(buf)
	buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
	return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "netrw"
end

function M.allows(buf)
	buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
	return vim.api.nvim_buf_is_loaded(buf) and M.is_source(buf) and not vim.b[buf].nopack_large_file
end

-- Editing targets are ordinary source windows, including protected large files.
function M.is_editor(win)
	win = (win == nil or win == 0) and vim.api.nvim_get_current_win() or win
	return vim.api.nvim_win_is_valid(win)
		and M.is_source(vim.api.nvim_win_get_buf(win))
		and vim.api.nvim_win_get_config(win).relative == ""
		and not vim.wo[win].previewwindow
end

-- Background results must still belong to the source they were requested for.
function M.source_context(buf)
	buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
	return {
		buf = buf,
		file = vim.api.nvim_buf_get_name(buf),
		filetype = vim.bo[buf].filetype,
		tick = vim.api.nvim_buf_get_changedtick(buf),
	}
end

function M.source_unchanged(context)
	local buf = context.buf
	return vim.api.nvim_buf_is_loaded(buf)
		and M.is_source(buf)
		and vim.api.nvim_buf_get_name(buf) == context.file
		and vim.bo[buf].filetype == context.filetype
		and vim.api.nvim_buf_get_changedtick(buf) == context.tick
end

function M.guard(callback)
	return function(...)
		if M.allows(0) then
			return callback(...)
		end
	end
end

function M.restrict(buf)
	if vim.b[buf].nopack_large_file then
		return
	end
	vim.b[buf].nopack_large_file = true
	vim.api.nvim_exec_autocmds("User", { pattern = "NopackBufferRestricted", data = { buf = buf }, modeline = false })
end

return M
