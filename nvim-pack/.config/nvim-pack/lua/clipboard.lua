-- -------------------------------------
-- Clipboard over SSH: native OSC52 copy, with the system paste provider unchanged
-- -------------------------------------
do
	local highlight_yank = vim.hl.hl_op or vim.hl.on_yank
	local copy_osc52 = require("vim.ui.clipboard.osc52").copy("+")
	vim.opt.clipboard = "unnamedplus"
	vim.api.nvim_create_autocmd("TextYankPost", {
		group = vim.api.nvim_create_augroup("highlight_yank", { clear = true }),
		callback = function()
			highlight_yank({ higroup = "IncSearch", timeout = 500 })
			if vim.v.event.operator == "y" and vim.v.event.regname == "" then
				local lines = vim.deepcopy(vim.v.event.regcontents)
				if vim.v.event.regtype == "V" then
					lines[#lines + 1] = ""
				end
				copy_osc52(lines)
			end
		end,
	})
end
