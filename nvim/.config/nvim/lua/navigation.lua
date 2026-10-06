local policy = require("buffer_policy")
local shared = require("state")

-- =========================================
-- ====== FILE TREE: TOGGLE / REVEAL =====
-- =========================================
-- <leader>e: open at the project root and expand folders leading to the current file.
-- Project discovery functions are defined in PROJECT ROOT and called when the keymap runs.

local explorer = require("explorer")
vim.keymap.set("n", "<leader>e", function()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if explorer.is_buffer(buf) then
			vim.api.nvim_win_call(win, function()
				vim.fn.maparg("<C-c>", "n", false, true).callback()
			end)
			return
		end
	end
	local file = policy.is_source(0) and vim.api.nvim_buf_get_name(0) or ""
	explorer.open(shared.project_root(), true, file)
end, { silent = true, nowait = true, desc = "Toggle editable file explorer" })

-- =========================================
-- ========= EDITOR WINDOW TARGET ========
-- =========================================
-- Find an editor window for files or buffers selected from the tree.
shared.focus_editor = function()
	if policy.is_editor(0) then
		return
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if policy.is_editor(win) then
			vim.api.nvim_set_current_win(win)
			return
		end
	end
	vim.cmd("botright vnew")
end

function shared.select_buffer(buf)
	shared.focus_editor()
	vim.api.nvim_set_current_buf(buf)
end
