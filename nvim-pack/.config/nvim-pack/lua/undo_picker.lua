local M = {}

function M.open()
	local source = vim.api.nvim_get_current_buf()
	local tick = vim.api.nvim_buf_get_changedtick(source)
	local scratch = vim.api.nvim_create_buf(false, true)
	local undo = vim.fn.tempname()
	local prompt
	local function cleanup()
		vim.fn.delete(undo)
		if vim.api.nvim_buf_is_valid(scratch) then
			vim.api.nvim_buf_delete(scratch, { force = true })
		end
	end
	-- telescope-undo traverses undo states. Run it on a copy so previews never
	-- mutate the editing buffer, its changedtick, LSP document or peer session.
	local ok, err = xpcall(function()
		vim.cmd.wundo({ undo, bang = true })
		vim.api.nvim_buf_set_lines(scratch, 0, -1, false, vim.api.nvim_buf_get_lines(source, 0, -1, false))
		vim.bo[scratch].fileformat = vim.bo[source].fileformat
		vim.bo[scratch].endofline = vim.bo[source].endofline
		local telescope = require("telescope")
		telescope.load_extension("undo")
		vim.api.nvim_buf_call(scratch, function()
			vim.cmd.rundo({ undo, mods = { silent = true } })
			telescope.extensions.undo.undo({
				attach_mappings = function(buf)
					prompt = buf
					vim.api.nvim_create_autocmd("BufWipeout", {
						buffer = buf,
						once = true,
						callback = function()
							vim.schedule(cleanup)
						end,
					})
					return true
				end,
				mappings = { i = {}, n = {} },
			})
		end)
		-- nvim_buf_call restores the editor window after the picker was created.
		vim.api.nvim_set_current_win(vim.fn.bufwinid(prompt))
		local function restore()
			local entry = require("telescope.actions.state").get_selected_entry()
			if not entry then
				return
			end
			if not vim.api.nvim_buf_is_valid(source) or vim.api.nvim_buf_get_changedtick(source) ~= tick then
				vim.notify("Buffer changed while browsing undo history; reopen the picker", vim.log.levels.WARN)
				return
			end
			local seq = entry.value.seq
			require("telescope.actions").close(prompt)
			vim.api.nvim_buf_call(source, function()
				vim.cmd.undo(seq)
			end)
		end
		for _, mode in ipairs({ "i", "n" }) do
			vim.keymap.set(mode, "<CR>", restore, { buffer = prompt, silent = true })
			vim.keymap.set(mode, "<C-r>", restore, { buffer = prompt, silent = true })
		end
		vim.keymap.set("n", "u", restore, { buffer = prompt, silent = true })
		vim.keymap.set("i", "<C-CR>", restore, { buffer = prompt, silent = true })
	end, debug.traceback)
	vim.fn.delete(undo)
	if not ok then
		cleanup()
		vim.notify(err, vim.log.levels.ERROR)
	end
end

return M
