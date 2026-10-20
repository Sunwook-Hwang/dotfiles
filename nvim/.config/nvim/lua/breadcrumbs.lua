local policy = require("buffer_policy")
local M = {}
local enabled = false
local symbols = require("breadcrumb_symbols").setup(function()
	return enabled
end)

-- Render the cached LSP hierarchy without starting requests or guessing from text.
function M.is_enabled()
	return enabled
end
function M.status(win)
	local buf = vim.api.nvim_win_get_buf(win)
	local parts = {}
	for _, symbol in ipairs(symbols.get_symbols(buf, win, vim.api.nvim_win_get_cursor(win))) do
		local name = symbol.name:gsub("[%c]", " "):gsub("%%", "%%%%")
		parts[#parts + 1] = " > %" .. (symbol.selection.start.line + 1) .. "@v:lua.NopackContextJump@" .. name .. "%X"
	end
	return table.concat(parts)
end

function _G.NopackContextJump(line, _, button)
	if button ~= "l" then
		return
	end
	local win = vim.fn.getmousepos().winid
	if vim.api.nvim_win_is_valid(win) and policy.is_editor(win) and policy.allows(vim.api.nvim_win_get_buf(win)) then
		vim.api.nvim_set_current_win(win)
		vim.cmd("normal! m'")
		vim.api.nvim_win_set_cursor(win, { math.min(line, vim.api.nvim_buf_line_count(0)), 0 })
		vim.cmd("normal! zvzz")
	end
end

vim.keymap.set("n", "<leader>Tb", function()
	enabled = not enabled
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		symbols.clear(buf)
	end
	if enabled then
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if policy.is_editor(win) then
				symbols.refresh(vim.api.nvim_win_get_buf(win))
			end
		end
	end
	vim.cmd("redrawstatus")
	vim.notify("Statusline context: " .. (enabled and "on" or "off"))
end, { desc = "Toggle breadcrumbs" })

return M
