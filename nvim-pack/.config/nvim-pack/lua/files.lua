local policy = require("buffer_policy")
local native_file_watch = vim.fn.has("nvim-0.13") == 1

-- Returning from an internal terminal does not necessarily trigger FocusGained.
local file_check_pending = false
local file_check_all, file_check_buffers = false, {}
local function check_external_files(buf)
	if buf == nil then
		file_check_all = true
	elseif policy.is_source(buf) then
		file_check_buffers[buf] = true
	else
		return
	end
	if file_check_pending then
		return
	end
	file_check_pending = true
	vim.schedule(function()
		file_check_pending = false
		local all, buffers = file_check_all, file_check_buffers
		file_check_all, file_check_buffers = false, {}
		if vim.fn.getcmdwintype() == "" and not vim.api.nvim_get_mode().mode:match("^[ct]") then
			if all then
				vim.cmd("checktime")
			else
				for target in pairs(buffers) do
					if vim.api.nvim_buf_is_loaded(target) and policy.is_source(target) then
						vim.cmd("checktime " .. target)
					end
				end
			end
		end
	end)
end
local file_changes = vim.api.nvim_create_augroup("pack-file-changes", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FocusGained", "ShellCmdPost", "TermLeave", "TermClose" }, {
	group = file_changes,
	callback = function(args)
		-- Navigation checks only its source; returning from outside checks all files.
		if args.event == "BufEnter" or args.event == "WinEnter" then
			if not native_file_watch then
				check_external_files(args.buf)
			end
		else
			check_external_files()
		end
	end,
})
vim.api.nvim_create_autocmd("FileChangedShellPost", {
	group = file_changes,
	callback = function(args)
		if policy.is_source(args.buf) and not vim.bo[args.buf].modified then
			vim.notify("Reloaded external file changes: " .. vim.fn.fnamemodify(args.file, ":~:."))
		end
	end,
})
