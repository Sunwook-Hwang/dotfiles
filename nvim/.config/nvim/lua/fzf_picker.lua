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
	local preview_buf, preview_win, request
	local generation, selected_index = 0, nil
	function state.close(accepted)
		if state.closed then
			return
		end
		state.closed = true
		if request then
			vim.api.nvim_del_autocmd(request)
			request = nil
		end
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
		if preview_win and vim.api.nvim_win_is_valid(preview_win) then
			vim.api.nvim_win_close(preview_win, true)
		end
		if preview_buf and vim.api.nvim_buf_is_valid(preview_buf) then
			vim.api.nvim_buf_delete(preview_buf, { force = true })
		end
		vim.fn.delete(input)
		vim.fn.delete(output)
		local focus = accepted == true and policy.is_editor(target) and target or origin
		if vim.api.nvim_win_is_valid(focus) then
			vim.api.nvim_set_current_win(focus)
		end
		if shared.active_picker == state then
			shared.active_picker = nil
		end
	end
	buf = vim.api.nvim_create_buf(false, true)
	vim.b[buf].nopack_picker_role = "fzf"
	vim.bo[buf].bufhidden = "wipe"
	local width, height = math.max(1, math.floor(vim.o.columns * 0.9)), math.max(1, math.floor((vim.o.lines - 4) * 0.9))
	local left_width = width >= 70 and math.floor((width - 2) / 2) or width
	local row, col =
		math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
		math.max(0, math.floor((vim.o.columns - width - 2) / 2))
	win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = title,
		width = left_width,
		height = height,
		row = row,
		col = col,
	})
	if left_width < width then
		preview_buf = vim.api.nvim_create_buf(false, true)
		vim.b[preview_buf].nopack_picker_role = "preview"
		vim.bo[preview_buf].bufhidden = "wipe"
		preview_win = vim.api.nvim_open_win(preview_buf, false, {
			relative = "editor",
			style = "minimal",
			border = "rounded",
			title = "preview",
			width = width - left_width - 2,
			height = height,
			row = row,
			col = col + left_width + 2,
			focusable = false,
		})
		vim.wo[preview_win].number = true
		vim.wo[preview_win].wrap = false
	end
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = preview_win and { tostring(win), tostring(preview_win) } or tostring(win),
		once = true,
		callback = state.close,
	})
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Collecting files..." })
	vim.bo[buf].modified = false
	vim.bo[buf].modifiable = false
	vim.keymap.set("n", "<Esc>", state.close, { buffer = buf, silent = true })
	vim.keymap.set("n", "<C-c>", state.close, { buffer = buf, silent = true })
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
		local file, err = io.open(input, "wb")
		if file then
			local written
			written, err = file:write(table.concat(labels, "\0"), "\0")
			local closed, close_err = file:close()
			err = written and not closed and close_err or err
		end
		if err then
			state.close()
			vim.notify("Could not prepare fzf input: " .. err, vim.log.levels.ERROR)
			return
		end
		vim.api.nvim_set_current_win(win)
		if preview_buf then
			request = vim.api.nvim_create_autocmd("TermRequest", {
				buffer = buf,
				callback = function(ev)
					local index = tonumber(ev.data.sequence:match("^\27%]51;flash%-fzf:(%-?%d+)$"))
					index = index and index + 1
					if state.closed or not index or index == selected_index then
						return
					end
					selected_index = index
					generation = generation + 1
					if not items[index] then
						vim.bo[preview_buf].syntax = ""
						vim.bo[preview_buf].modifiable = true
						vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, { "No matches" })
						vim.bo[preview_buf].modifiable = false
						return
					end
					local version, filename = generation, items[index].filename
					local function current()
						return not state.closed and generation == version and vim.api.nvim_buf_is_valid(preview_buf)
					end
					-- Share the native asynchronous reader; bound long-line files to one 64 KiB chunk.
					shared.read_preview(filename, 1, height, current, function(lines)
						vim.bo[preview_buf].modifiable = true
						vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines or { "No text preview" })
						vim.bo[preview_buf].modifiable = false
						local syntax = lines and (vim.filetype.match({ filename = filename, buf = preview_buf }) or "")
							or ""
						if vim.bo[preview_buf].syntax ~= syntax then
							vim.bo[preview_buf].syntax = syntax
						end
					end, 65536)
				end,
			})
		end
		-- fzf's preview worker cancels obsolete notifications without blocking input.
		-- Size zero keeps rendering in Neovim; only the input index crosses the PTY.
		local preview = preview_buf
				and " --preview-window=0 --preview " .. vim.fn.shellescape(
					[[printf '\033]51;flash-fzf:%s\007' {n} > /dev/tty]]
				) .. " --bind " .. vim.fn.shellescape(
					[[zero:preview(printf '\033]51;flash-fzf:-1\007' > /dev/tty)]]
				)
			or ""
		local command = vim.fn.shellescape(executable)
			.. " --read0 --print0 --no-multi --layout=reverse"
			.. preview
			.. " < "
			.. vim.fn.shellescape(input)
			.. " > "
			.. vim.fn.shellescape(output)
		job = vim.fn.jobstart({ "sh", "-c", command }, {
			term = true,
			cwd = root,
			-- Keep inherited --expect/--print-query/bindings from changing the picker protocol.
			-- Notifications use a POSIX builtin, without loading the user's shell configuration.
			env = { FZF_DEFAULT_OPTS = "", FZF_DEFAULT_OPTS_FILE = "", SHELL = "sh" },
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
					state.close(filename ~= nil)
					if filename then
						if not policy.is_editor(target) then
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
