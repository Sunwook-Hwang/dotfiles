local policy = require("buffer_policy")
local shared = require("state")
local M = {}
local namespace = vim.api.nvim_create_namespace("nopack-git-preview")
local deleted_namespace = vim.api.nvim_create_namespace("nopack-git-deleted")
local busy, history, previews, deleted = {}, {}, {}, {}
local show_deleted = false
local limit = 256 * 1024

-- Keep line terminators: patches must preserve both CRLF and missing final newlines.
local function records(text)
	local lines = {}
	for line in text:gmatch("[^\n]*\n") do
		lines[#lines + 1] = line
	end
	local tail = text:match("([^\n]+)$")
	if tail then
		lines[#lines + 1] = tail
	end
	return lines
end
local function diff(a, b)
	return vim.text.diff(a, b, { result_type = "indices", algorithm = "histogram" })
end
local function slice(lines, start, count)
	return vim.list_slice(lines, start + 1, start + count)
end

-- Convert a cursor hunk / visual line range into matching index and buffer spans.
local function selected(hunks, top, bottom, whole)
	local result = {}
	for _, h in ipairs(hunks) do
		local a, m, b, n = unpack(h)
		local anchor = math.max(1, b)
		if whole or (anchor <= bottom and math.max(anchor, b + n - 1) >= top) then
			local first = whole and 0 or math.max(0, top - b)
			local last = whole and n or math.min(n, bottom - b + 1)
			if n == 0 then
				first, last = 0, 0
			end
			local old_first = math.min(first, m)
			local old_last = last == n and m or math.min(last, m)
			result[#result + 1] = {
				(m == 0 and a or a - 1) + old_first,
				old_last - old_first,
				(n == 0 and b or b - 1) + first,
				last - first,
			}
		end
	end
	return result
end
local function replace(base, current, changes, reverse)
	local old, new = records(base), records(current)
	local source, target, offset = reverse and new or old, {}, 1
	-- Append unchanged spans and replacements once; middle insertions/removals
	-- shift the remaining array for every line in a large hunk.
	for _, change in ipairs(changes) do
		local a, m, b, n = unpack(change)
		local start, count, lines = a, m, slice(new, b, n)
		if reverse then
			start, count, lines = b, n, slice(old, a, m)
		end
		vim.list_extend(target, source, offset, start)
		vim.list_extend(target, lines)
		offset = start + count + 1
	end
	vim.list_extend(target, source, offset)
	return table.concat(target)
end
local function quote(path)
	return '"' .. path:gsub('[%c\\"]', function(c)
		return string.format("\\%03o", c:byte())
	end) .. '"'
end
local function patch(path, old, new, mode, exists)
	local a, b = quote("a/" .. path), quote("b/" .. path)
	local header = "diff --git " .. a .. " " .. b .. "\n"
	if not exists then
		header = header .. "new file mode " .. mode .. "\n"
	end
	-- Full context rejects stale index contents instead of guessing a zero-context offset.
	return header
		.. "--- "
		.. (exists and a or "/dev/null")
		.. "\n+++ "
		.. b
		.. "\n"
		.. vim.text.diff(old, new, { algorithm = "histogram", ctxlen = math.max(#records(old), #records(new)) + 1 })
end
local function message(text)
	vim.notify("Git: " .. text, vim.log.levels.WARN)
end
local function buffer_text(buf, base)
	-- Preserve the index's normalized EOLs; Unix buffers already contain literal CRs.
	local separator = vim.bo[buf].fileformat == "dos" and base:find("\r\n", 1, true) and "\r\n" or "\n"
	local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), separator)
	if vim.bo[buf].endofline then
		text = text .. separator
	end
	if vim.bo[buf].bomb then
		text = "\239\187\191" .. text
	end
	return text
end

-- One explicit action per repository. Never cancel an index write to start another.
local function snapshot(callback)
	local buf = vim.api.nvim_get_current_buf()
	if not policy.allows(buf) then
		return
	end
	local context = policy.source_context(buf)
	local root = context.file ~= "" and shared.find_git_root(vim.fs.dirname(context.file))
	if not root or vim.fn.executable("git") == 0 then
		message("Open a file in a Git repository")
		return
	end
	if busy[root] then
		message("An action is still running in this repository")
		return
	end
	if vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) > limit then
		message("Hunk actions are limited to 256 KiB files")
		return
	end
	if vim.bo[buf].fileencoding ~= "" and vim.bo[buf].fileencoding ~= "utf-8" then
		message("Hunk actions require UTF-8 text")
		return
	end
	local state = { buf = buf, context = context, root = root, path = context.file:sub(#root + 2) }
	busy[root] = state
	function state.finish()
		if busy[root] == state then
			busy[root] = nil
		end
	end
	function state.valid()
		return busy[root] == state and policy.allows(buf) and policy.source_unchanged(context)
	end
	function state.run(args, input, done)
		shared.run_command(
			"git-action:" .. root,
			vim.list_extend({ "git", "--no-pager", "--literal-pathspecs" }, args),
			{
				cwd = root,
				stdin = input,
				max_bytes = limit,
				atomic = state.writing,
				failed = state.finish,
			},
			done
		)
	end
	state.run({ "ls-files", "--stage", "-z", "--", state.path }, nil, function(output)
		if not state.valid() then
			state.finish()
			return
		end
		local mode, oid, stage = output:match("^(%d+) (%x+) (%d)\t")
		if stage and (stage ~= "0" or (mode ~= "100644" and mode ~= "100755")) then
			message("Resolve index conflicts first; only regular files support hunk actions")
			state.finish()
			return
		end
		state.exists, state.mode = oid ~= nil, mode or "100644"
		if not oid then
			local info = vim.uv.fs_lstat(context.file)
			if info and info.type ~= "file" then
				message("Only regular files support hunk actions")
				state.finish()
				return
			end
			if info and bit.band(info.mode, 73) ~= 0 then
				state.mode = "100755"
			end
		end
		local function ready(base)
			if not state.valid() then
				state.finish()
				return
			end
			state.base, state.current = base, buffer_text(buf, base)
			if base:find("\0", 1, true) or state.current:find("\0", 1, true) then
				message("Binary buffers do not support hunk actions")
				state.finish()
				return
			end
			state.hunks = diff(base, state.current)
			callback(state)
		end
		if oid then
			state.run({ "cat-file", "blob", oid }, nil, ready)
		else
			ready("")
		end
	end)
	return state
end

local refresh
local function write_index(state, target, undo)
	local entry = undo
		or {
			after = target,
			patch = patch(state.path, state.base, target, state.mode, state.exists),
		}
	if undo and state.base ~= undo.after then
		message("Index changed since staging; refusing to overwrite other staged changes")
		state.finish()
		return
	end
	local args = { "apply", "--cached", "--whitespace=nowarn" }
	if undo then
		args[#args + 1] = "--reverse"
	end
	args[#args + 1] = "-"
	state.writing = true
	state.run(args, entry.patch, function()
		local key = state.buf
		if vim.api.nvim_buf_is_loaded(key) and vim.api.nvim_buf_get_name(key) == state.context.file then
			history[key] = history[key] or {}
			if undo then
				table.remove(history[key])
			else
				history[key][#history[key] + 1] = entry
			end
		end
		state.finish()
		refresh(state.buf)
		vim.notify(undo and "Git: staging undone" or "Git: staged")
	end)
end
local function visible_lines(text, format)
	text = text:gsub("^\239\187\191", "")
	if format == "dos" then
		text = text:gsub("\r\n", "\n")
	end
	local lines = vim.split(text, "\n", { plain = true })
	if text:sub(-1) == "\n" then
		table.remove(lines)
	end
	if #lines == 0 then
		lines = { "" }
	end
	return lines
end
local function reset_buffer(state, target)
	if not state.valid() or not vim.bo[state.buf].modifiable then
		state.finish()
		return
	end
	local old = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
	local new = visible_lines(target, vim.bo[state.buf].fileformat)
	local edits = diff(table.concat(old, "\n") .. "\n", table.concat(new, "\n") .. "\n")
	vim.api.nvim_buf_call(state.buf, function()
		for i = #edits, 1, -1 do
			if i < #edits then
				vim.cmd("undojoin")
			end
			local a, m, b, n = unpack(edits[i])
			local start = m == 0 and a or a - 1
			vim.api.nvim_buf_set_lines(state.buf, start, start + m, false, slice(new, n == 0 and b or b - 1, n))
		end
	end)
	vim.bo[state.buf].endofline = target:sub(-1) == "\n"
	vim.bo[state.buf].bomb = target:sub(1, 3) == "\239\187\191"
	state.finish()
	refresh(state.buf)
end
local function action(kind, visual, whole)
	local top, bottom = vim.fn.line("."), vim.fn.line(".")
	if visual then
		top, bottom = math.min(top, vim.fn.line("v")), math.max(bottom, vim.fn.line("v"))
		vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
	end
	snapshot(function(state)
		local changes
		if whole then
			changes = selected(state.hunks, 1, math.huge, true)
		elseif visual then
			changes = selected(state.hunks, top, bottom, false)
		else
			local hunk
			for _, h in ipairs(state.hunks) do
				if top >= math.max(1, h[3]) and top <= math.max(1, h[3] + math.max(1, h[4]) - 1) then
					hunk = h
					break
				end
			end
			changes = hunk and selected({ hunk }, 1, math.huge, true) or {}
		end
		if #changes == 0 then
			message("No unstaged hunk at this position")
			state.finish()
			return
		end
		local target = replace(state.base, state.current, changes, kind == "reset")
		if kind == "stage" then
			write_index(state, target)
		else
			reset_buffer(state, target)
		end
	end)
end

local function virtual_lines(base_lines, hunk)
	local lines = {}
	for _, line in ipairs(slice(base_lines, hunk[1] - 1, hunk[2])) do
		lines[#lines + 1] = { { "- " .. line:gsub("[\r\n]+$", ""), "DiffDelete" } }
	end
	return lines
end
function M.clear(buf)
	if deleted[buf] then
		vim.api.nvim_buf_clear_namespace(buf, deleted_namespace, 0, -1)
		deleted[buf] = nil
	end
end
function M.render_deleted(buf, base, hunks)
	M.clear(buf)
	if not show_deleted then
		return
	end
	local base_lines
	for _, h in ipairs(hunks) do
		if h[2] > 0 then
			base_lines = base_lines or records(base)
			deleted[buf] = true
			vim.api.nvim_buf_set_extmark(buf, deleted_namespace, math.max(0, h[3] - 1), 0, {
				virt_lines = virtual_lines(base_lines, h),
				virt_lines_above = h[4] > 0 or h[3] == 0,
			})
		end
	end
end
local function at_cursor(callback, wait)
	local row, win = vim.fn.line("."), vim.api.nvim_get_current_win()
	local request = snapshot(function(state)
		state.finish()
		if
			not vim.api.nvim_win_is_valid(win)
			or vim.api.nvim_get_current_win() ~= win
			or vim.api.nvim_get_current_buf() ~= state.buf
			or vim.fn.line(".") ~= row
		then
			return
		end
		for _, h in ipairs(state.hunks) do
			if row >= math.max(1, h[3]) and row <= math.max(1, h[3] + math.max(1, h[4]) - 1) then
				callback(state, h)
				return
			end
		end
		message("No unstaged hunk at this position")
	end)
	-- Operator-pending mappings must finish selection before returning to Normal mode.
	if wait and request then
		vim.wait(5500, function()
			return busy[request.root] ~= request
		end, 10)
	end
end
function M.setup(on_change)
	refresh = on_change
	for _, item in ipairs({
		{ "gs", "stage", false },
		{ "gr", "reset", false },
		{ "gS", "stage", true },
		{ "gR", "reset", true },
	}) do
		shared.map("n", "<leader>" .. item[1], function()
			action(item[2], false, item[3])
		end, "Git: " .. item[2] .. (item[3] and " buffer" or " hunk"))
		if not item[3] then
			shared.map("x", "<leader>" .. item[1], function()
				action(item[2], true, false)
			end, "Git: " .. item[2] .. " selection")
		end
	end
	shared.map("n", "<leader>gU", function()
		snapshot(function(state)
			local stack = history[state.buf] or {}
			if #stack == 0 then
				message("No staging to undo in this session")
				state.finish()
				return
			end
			write_index(state, nil, stack[#stack])
		end)
	end, "Git: Undo stage hunk")
	shared.map("n", "<leader>gv", function()
		at_cursor(function(state, h)
			vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
			previews[state.buf] = true
			vim.api.nvim_buf_set_extmark(state.buf, namespace, math.max(0, h[3] - 1), 0, {
				virt_lines = virtual_lines(records(state.base), h),
				virt_lines_above = h[4] > 0 or h[3] == 0,
			})
			if h[4] > 0 then
				vim.api.nvim_buf_set_extmark(state.buf, namespace, h[3] - 1, 0, {
					end_row = h[3] - 1 + h[4],
					hl_group = "DiffAdd",
					hl_eol = true,
				})
			end
		end)
	end, "Git: Preview hunk (inline)")
	shared.map("n", "<leader>gt", function()
		show_deleted = not show_deleted
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(buf) then
				M.clear(buf)
				if show_deleted and vim.fn.bufwinid(buf) ~= -1 then
					refresh(buf)
				end
			end
		end
		vim.notify("Deleted lines: " .. (show_deleted and "on" or "off"))
	end, "Git: Toggle deleted")
	shared.map({ "o", "x" }, "ih", function()
		at_cursor(function(_, h)
			local mode = vim.fn.mode()
			if mode == "v" or mode == "V" or mode == "\22" then
				vim.cmd("normal! " .. vim.keycode("<Esc>"))
			end
			vim.cmd("normal! " .. math.max(1, h[3]) .. "GV" .. math.max(1, h[3] + math.max(1, h[4]) - 1) .. "G")
		end, true)
	end, "Git: inner hunk")
	shared.map("n", "<leader>gB", function()
		local row = vim.fn.line(".")
		snapshot(function(state)
			state.run(
				{ "blame", "--line-porcelain", "--contents", "-", "-L", row .. "," .. row, "--", state.path },
				state.current,
				function(output)
					if not state.valid() then
						state.finish()
						return
					end
					local hash = output:match("^(%x+)")
					local function display(text)
						local valid = state.valid()
							and vim.api.nvim_get_current_buf() == state.buf
							and vim.fn.line(".") == row
						state.finish()
						if valid then
							vim.lsp.util.open_floating_preview(
								vim.split(text, "\n"),
								"git",
								{ border = "single", focusable = true }
							)
						end
					end
					if not hash or hash:match("^0+$") then
						display("Not committed yet")
						return
					end
					state.run({ "show", "--format=fuller", "--no-ext-diff", hash, "--", state.path }, nil, display)
				end
			)
		end)
	end, "Git: Blame (full)")
	local group = vim.api.nvim_create_augroup("nopack-git-actions", { clear = true })
	vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "TextChanged", "TextChangedI", "BufLeave" }, {
		group = group,
		callback = function(args)
			if previews[args.buf] then
				vim.api.nvim_buf_clear_namespace(args.buf, namespace, 0, -1)
				previews[args.buf] = nil
			end
			if args.event == "TextChanged" or args.event == "TextChangedI" then
				M.clear(args.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "BufUnload", "BufFilePost" }, {
		group = group,
		callback = function(args)
			vim.api.nvim_buf_clear_namespace(args.buf, namespace, 0, -1)
			history[args.buf], previews[args.buf] = nil, nil
			M.clear(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "NopackCancel", "NopackBufferRestricted" },
		callback = function(args)
			for root, state in pairs(busy) do
				if not state.writing and (not args.data or state.buf == args.data.buf) then
					shared.cancel_command("git-action:" .. root)
					busy[root] = nil
				end
			end
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(buf) and (not args.data or buf == args.data.buf) then
					vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
					M.clear(buf)
					previews[buf] = nil
				end
			end
		end,
	})
end
return M
