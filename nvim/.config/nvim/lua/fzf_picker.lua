local shared = require("state")
local policy = require("buffer_policy")
local M = {}

-- Run the installed fzf binary in an unlisted terminal; keep shell jobs and editor windows intact.
function M.open(title, root, executable, cancel)
	if shared.active_picker then
		shared.active_picker.close()
	end
	local origin = vim.api.nvim_get_current_win()
	shared.focus_editor()
	local target = vim.api.nvim_get_current_win()
	local state = { closed = false }
	local input, output = vim.fn.tempname(), vim.fn.tempname()
	local buf, win, job
	function state.close()
		if state.closed then
			return
		end
		state.closed = true
		if cancel then
			cancel()
		end
		if job and job > 0 then
			vim.fn.jobstop(job)
		end
		if win and vim.api.nvim_win_is_valid(win) then
			if vim.api.nvim_get_current_win() == win then
				vim.cmd("stopinsert")
			end
			vim.api.nvim_win_close(win, true)
		end
		if buf and vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		vim.fn.delete(input)
		vim.fn.delete(output)
		if vim.api.nvim_win_is_valid(origin) then
			vim.api.nvim_set_current_win(origin)
		end
		if shared.active_picker == state then
			shared.active_picker = nil
		end
	end
	function state.set_items(items)
		if state.closed then
			return
		end
		if #items == 0 then
			state.close()
			vim.notify("No results: " .. title)
			return
		end
		local labels, lookup = {}, {}
		local prefix = root:gsub("/+$", "") .. "/"
		for _, item in ipairs(items) do
			local label = item.filename:sub(1, #prefix) == prefix and item.filename:sub(#prefix + 1) or item.filename
			labels[#labels + 1] = label
			lookup[label] = item.filename
		end
		local file = assert(io.open(input, "wb"))
		file:write(table.concat(labels, "\0"), "\0")
		file:close()
		buf = vim.api.nvim_create_buf(false, true)
		vim.b[buf].nopack_picker_role = "fzf"
		vim.bo[buf].bufhidden = "wipe"
		local width, height =
			math.max(1, math.floor(vim.o.columns * 0.9)), math.max(1, math.floor((vim.o.lines - 4) * 0.9))
		win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			style = "minimal",
			border = "rounded",
			title = title,
			width = width,
			height = height,
			row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
			col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
		})
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(win),
			once = true,
			callback = state.close,
		})
		local command = vim.fn.shellescape(executable)
			.. " --read0 --print0 --no-multi --layout=reverse --preview "
			.. vim.fn.shellescape("head -c 65536 -- {} | head -n 200")
			.. " < "
			.. vim.fn.shellescape(input)
			.. " > "
			.. vim.fn.shellescape(output)
		job = vim.fn.jobstart({ "sh", "-c", command }, {
			term = true,
			cwd = root,
			on_exit = function(_, code)
				vim.schedule(function()
					if state.closed then
						return
					end
					job = nil
					local result = io.open(output, "rb")
					local selected = result and result:read("*a") or ""
					if result then
						result:close()
					end
					local filename = code == 0 and lookup[selected:gsub("%z$", "")] or nil
					state.close()
					if filename then
						if policy.is_editor(target) then
							vim.api.nvim_set_current_win(target)
						else
							shared.focus_editor()
						end
						vim.cmd("edit " .. vim.fn.fnameescape(filename))
					elseif code ~= 0 and code ~= 1 and code ~= 130 then
						vim.notify("fzf exited with code " .. code, vim.log.levels.ERROR)
					end
				end)
			end,
		})
		if job <= 0 then
			state.close()
			vim.notify("Could not start fzf", vim.log.levels.ERROR)
			return
		end
		vim.cmd("startinsert")
	end
	shared.active_picker = state
	return state
end

return M
