local policy = require("buffer_policy")
local M = {}

local function invalidate_split_zoom(tab)
	if not vim.api.nvim_tabpage_is_valid(tab) or not vim.t[tab].pack_zoom then
		return
	end
	local editors = 0
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if policy.is_editor(win) then
			editors = editors + 1
			if editors > 1 then
				vim.t[tab].pack_zoom = nil
				return
			end
		end
	end
end
vim.api.nvim_create_autocmd("WinNew", {
	group = vim.api.nvim_create_augroup("pack-window-zoom", { clear = true }),
	callback = function()
		local tab = vim.api.nvim_get_current_tabpage()
		if vim.t[tab].pack_zoom then
			-- Utility splits can initially inherit an editor buffer; classify after setup.
			vim.schedule(function()
				invalidate_split_zoom(tab)
			end)
		end
	end,
})
local function restore_window_zoom(tab, win)
	invalidate_split_zoom(tab)
	local zoom = vim.t[tab].pack_zoom
	if not zoom then
		return
	end
	if not policy.is_editor(zoom.source) or not policy.is_editor(win) then
		vim.t[tab].pack_zoom = nil
		vim.notify("Original editor window closed; keeping the zoom tab")
		return
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if vim.wo[zoom.source].winfixbuf and vim.api.nvim_win_get_buf(zoom.source) ~= buf then
		vim.notify("Original window has winfixbuf enabled; unlock it before restoring zoom")
		return
	end
	local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
	vim.api.nvim_win_set_buf(zoom.source, buf)
	local windows = vim.tbl_filter(function(candidate)
		return vim.api.nvim_win_get_config(candidate).relative == ""
	end, vim.api.nvim_tabpage_list_wins(tab))
	if #windows == 1 then
		vim.api.nvim_set_current_win(win)
		vim.cmd("tabclose")
	else
		vim.t[tab].pack_zoom = nil
	end
	-- Preserve any splits added during zoom as a normal tab.
	vim.api.nvim_set_current_win(zoom.source)
	vim.fn.winrestview(view)
end
function M.restore_all()
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local zoom = vim.t[tab].pack_zoom
		if zoom then
			restore_window_zoom(tab, zoom.win)
		end
	end
end
local function toggle_window_zoom()
	if not policy.is_editor(0) then
		return
	end
	local tab = vim.api.nvim_get_current_tabpage()
	invalidate_split_zoom(tab)
	if vim.t.pack_zoom then
		restore_window_zoom(tab, vim.api.nvim_get_current_win())
	elseif #vim.api.nvim_tabpage_list_wins(tab) > 1 then
		local source = vim.api.nvim_get_current_win()
		vim.cmd("tab split")
		vim.t.pack_zoom = { source = source, win = vim.api.nvim_get_current_win() }
	end
end
vim.keymap.set("n", "<C-w>o", toggle_window_zoom, { silent = true, desc = "Toggle editor window zoom" })
vim.keymap.set("n", "<C-w><C-o>", toggle_window_zoom, { silent = true, desc = "Toggle editor window zoom" })

return M
