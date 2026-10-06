local policy = require("buffer_policy")
local shared = require("state")

-- =========================================
-- ====== RESULT PARSING / QUICKFIX ======
-- =========================================
-- 명령 출력은 줄 또는 NUL 단위로 분리합니다. 잘린 출력의 마지막 불완전 항목은 버립니다.
-- Quickfix는 picker에서 Ctrl-q로 명시적으로 내보낼 때 사용합니다.
function shared.records(output, separator, limited, maximum)
	local items, offset = {}, 1
	while not maximum or #items < maximum do
		local boundary = output:find(separator, offset, true)
		if not boundary then
			if not limited and offset <= #output then
				items[#items + 1] = output:sub(offset)
			end
			break
		end
		items[#items + 1] = output:sub(offset, boundary - 1)
		offset = boundary + #separator
	end
	return items
end
local function show_results(items, title)
	vim.fn.setqflist({}, " ", { title = title, items = items })
	if #items == 0 then
		vim.notify("No results: " .. title)
		return
	end
	shared.focus_editor()
	vim.cmd("botright copen")
	vim.bo.buflisted = false
	vim.opt_local.wrap = false
end
-- =========================================
-- ========== PICKER: SHARED UI ==========
-- =========================================
-- Telescope 대체 공통 UI: 입력 -> 결과 필터/갱신 -> 미리보기 -> 원래 편집 창에 선택 적용.
-- Ctrl-n/p·Tab: 후보 이동, Enter: 선택, Esc: 취소, Ctrl-q: quickfix.
-- 후보 표시 최대 200개. 디스크는 64 KiB씩 읽어 선택 줄 주변만 보관합니다.
local function read_preview(file, first, count, current, done)
	local uv = vim.uv
	uv.fs_open(
		file,
		"r",
		438,
		vim.schedule_wrap(function(err, fd)
			if err or not fd then
				if current() then
					done(nil)
				end
				return
			end
			local offset, row, prefix, lines = 0, 1, "", {}
			local last = first + count - 1
			local function finish(result)
				uv.fs_close(fd)
				if current() then
					done(result)
				end
			end
			local read
			read = function()
				if not current() then
					finish(nil)
					return
				end
				uv.fs_read(
					fd,
					65536,
					offset,
					vim.schedule_wrap(function(failure, data)
						if not current() or failure or (data and data:find("\0", 1, true)) then
							finish(nil)
							return
						end
						if not data or data == "" then
							if row >= first and prefix ~= "" then
								lines[#lines + 1] = prefix
							end
							finish(lines)
							return
						end
						offset = offset + #data
						local start = 1
						while start <= #data do
							local boundary = data:find("\n", start, true)
							if row >= first and #prefix < 500 then
								prefix = prefix
									.. data:sub(start, math.min((boundary or (#data + 1)) - 1, start + 499 - #prefix))
							end
							if not boundary then
								break
							end
							if row >= first then
								lines[#lines + 1] = prefix:gsub("\r$", "")
							end
							row, prefix, start = row + 1, "", boundary + 1
							if row > last then
								finish(lines)
								return
							end
						end
						read()
					end)
				)
			end
			read()
		end)
	)
end
shared.open_picker = function(title, opts)
	opts = opts or {}
	if shared.active_picker then
		shared.active_picker.close()
	end
	local origin = vim.api.nvim_get_current_win()
	shared.focus_editor()
	local target = vim.api.nvim_get_current_win()
	local width = math.max(24, math.min(vim.o.columns - 4, 120))
	local height = math.max(4, math.min(vim.o.lines - 8, 22))
	local scale = math.min(1.8, math.max(1, vim.o.columns - 4) / width, math.max(1, vim.o.lines - 8) / height)
	width = math.max(1, math.floor(width * scale + 0.5))
	height = math.max(1, math.floor(height * scale + 0.5))
	local preview_context = math.min(8, height - 1)
	local row, col =
		math.max(0, math.floor((vim.o.lines - height - 4) / 2)), math.max(0, math.floor((vim.o.columns - width) / 2))
	local list_width = (width >= 70 or opts.preview) and math.floor(width * 0.48) or width
	local state = { items = {}, matches = {}, index = 1, generation = 0, closed = false, windows = {}, buffers = {} }
	-- -------------------------------------
	-- Create prompt / result / preview windows
	-- -------------------------------------
	local function pane(role, pane_row, pane_col, pane_width, pane_height, enter)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.b[buf].nopack_picker_role = role
		vim.bo[buf].bufhidden = "wipe"
		local win = vim.api.nvim_open_win(buf, enter, {
			relative = "editor",
			row = pane_row,
			col = pane_col,
			width = pane_width,
			height = pane_height,
			style = "minimal",
			border = "rounded",
			title = role == "query" and title or role,
		})
		vim.wo[win][0].wrap = false
		state.windows[#state.windows + 1] = win
		state.buffers[#state.buffers + 1] = buf
		return buf, win
	end
	local list_buf, list_win = pane("results", row + 3, col, list_width, height, false)
	local preview_buf, preview_win
	if list_width < width then
		preview_buf, preview_win = pane("preview", row + 3, col + list_width + 2, width - list_width - 2, height, false)
		if not opts.preview then
			vim.b[preview_buf].nopack_preview_first = 1
			vim.wo[preview_win][0].number = true
			vim.wo[preview_win][0].signcolumn = "yes:1"
			vim.wo[preview_win][0].statuscolumn = "%s%{v:lnum + b:nopack_preview_first - 1}  "
		end
	end
	local query_buf, query_win = pane("query", row, col, width, 1, true)
	vim.wo[list_win][0].cursorline = true
	vim.wo[list_win][0].cursorlineopt = "line"
	vim.wo[list_win][0].winhighlight = "CursorLine:NopackPickerSelection,CursorLineNr:NopackPickerSelection"
	local group = vim.api.nvim_create_augroup("nopack-picker", { clear = true })
	local function fill(buf, lines)
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, #lines > 0 and lines or { "No matches" })
		vim.bo[buf].modifiable = false
	end
	-- -------------------------------------
	-- Preview: discard responses for an older selection
	-- -------------------------------------
	local preview_ns = vim.api.nvim_create_namespace("nopack-picker-preview")
	local preview_generation = 0
	local function preview(item)
		preview_generation = preview_generation + 1
		local version = preview_generation
		if not preview_buf then
			return
		end
		if opts.preview then
			if item then
				opts.preview(item, preview_buf, preview_win)
			end
			return
		end
		vim.api.nvim_buf_clear_namespace(preview_buf, preview_ns, 0, -1)
		fill(preview_buf, { "" })
		if not item then
			vim.bo[preview_buf].syntax = ""
			return
		end
		local function display(lines, first, filetype)
			if state.closed or version ~= preview_generation then
				return
			end
			local line = math.max(1, item.lnum or 1)
			local start = first and 1 or (line <= #lines and math.max(1, line - preview_context) or 1)
			local chunk = {}
			for i = start, math.min(#lines, start + height - 1) do
				chunk[#chunk + 1] = lines[i]:sub(1, 500)
			end
			fill(preview_buf, chunk)
			vim.b[preview_buf].nopack_preview_first = first or start
			local selected = line - (first or start)
			if selected >= 0 and selected < #chunk then
				local column = math.min(math.max(0, (item.col or 1) - 1), #chunk[selected + 1])
				vim.api.nvim_win_set_cursor(preview_win, { selected + 1, column })
				vim.api.nvim_buf_set_extmark(preview_buf, preview_ns, selected, 0, {
					sign_text = ">",
					sign_hl_group = "Search",
					number_hl_group = "CursorLineNr",
					line_hl_group = "CursorLine",
				})
			end
			-- Use bundled syntax without FileType events, ftplugins, or LSP startup.
			local syntax = filetype or vim.filetype.match({ filename = item.filename, buf = preview_buf }) or ""
			if vim.bo[preview_buf].syntax ~= syntax then
				vim.bo[preview_buf].syntax = syntax
			end
		end
		local buf = item.bufnr or (item.filename and vim.fn.bufnr(item.filename)) or -1
		if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then
			local first = math.max(0, (item.lnum or 1) - preview_context - 1)
			local lines = vim.api.nvim_buf_get_lines(buf, first, first + height, false)
			local filetype = vim.bo[buf].filetype
			display(lines, first + 1, filetype ~= "" and filetype or nil)
		elseif item.filename then
			local first = math.max(1, (item.lnum or 1) - preview_context)
			read_preview(item.filename, first, height, function()
				return not state.closed and version == preview_generation
			end, function(lines)
				if not lines then
					vim.bo[preview_buf].syntax = ""
					fill(preview_buf, { "No text preview" })
					return
				end
				display(lines, first)
			end)
		elseif item.text then
			vim.bo[preview_buf].syntax = ""
			fill(preview_buf, vim.split(item.text, "\n", { plain = true }))
		end
	end
	-- -------------------------------------
	-- Render and filter candidates
	-- -------------------------------------
	local function select_item()
		state.index = math.max(1, math.min(state.index, #state.matches))
		vim.api.nvim_win_set_cursor(list_win, { state.index, 0 })
		preview(state.matches[state.index])
		if opts.highlight then
			opts.highlight(state.matches[state.index])
		end
	end
	local function draw()
		if state.closed then
			return
		end
		local lines = {}
		for _, item in ipairs(state.matches) do
			lines[#lines + 1] = item.label:gsub("[%c]", " ")
		end
		fill(list_buf, lines)
		select_item()
	end
	local function filter()
		local query = vim.api.nvim_buf_get_lines(query_buf, 0, 1, false)[1] or ""
		state.matches = query == "" and vim.list_slice(state.items, 1, 200)
			or vim.fn.matchfuzzy(state.items, query, { key = "label", limit = 200 })
		state.index = 1
		draw()
	end
	function state.set_items(items)
		if state.closed then
			return
		end
		state.items = items
		if opts.live then
			state.matches = vim.list_slice(items, 1, 200)
			state.index = 1
			draw()
		else
			filter()
		end
	end
	-- -------------------------------------
	-- Close lifecycle: cancel work, restore focus, invoke cancellation once
	-- -------------------------------------
	function state.close(accepted)
		if state.closed then
			return
		end
		state.closed = true
		if opts.cancel then
			opts.cancel()
		end
		if not accepted and opts.on_cancel then
			opts.on_cancel()
		end
		vim.cmd("stopinsert")
		vim.api.nvim_del_augroup_by_id(group)
		for _, win in ipairs(state.windows) do
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
		if vim.api.nvim_win_is_valid(origin) then
			vim.api.nvim_set_current_win(origin)
		end
		if shared.active_picker == state then
			shared.active_picker = nil
		end
	end
	-- -------------------------------------
	-- Accept only the selected item into the original editor window
	-- -------------------------------------
	local function accept()
		if vim.api.nvim_get_current_win() == list_win then
			state.index = vim.api.nvim_win_get_cursor(list_win)[1]
		end
		local item = state.matches[state.index]
		if not item then
			return
		end
		state.close(true)
		if policy.is_editor(target) then
			vim.api.nvim_set_current_win(target)
		else
			shared.focus_editor()
		end
		if item.action then
			item.action()
			return
		end
		if item.bufnr and vim.api.nvim_buf_is_valid(item.bufnr) then
			vim.api.nvim_set_current_buf(item.bufnr)
		elseif item.filename then
			vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
		end
		if item.lnum then
			local line = math.min(item.lnum, vim.api.nvim_buf_line_count(0))
			vim.api.nvim_win_set_cursor(0, { math.max(1, line), math.max(0, (item.col or 1) - 1) })
			vim.cmd("normal! zz")
		end
	end
	local function move(delta)
		if #state.matches == 0 then
			return
		end
		state.index = (state.index + delta - 1) % #state.matches + 1
		select_item()
	end
	for _, buf in ipairs(state.buffers) do
		for _, key in ipairs({ "<Esc>", "<C-c>" }) do
			vim.keymap.set({ "n", "i" }, key, state.close, { buf = buf, nowait = true })
		end
		if opts.preview and preview_win then
			for _, key in ipairs({ "<C-f>", "<C-b>" }) do
				vim.keymap.set({ "n", "i" }, key, function()
					vim.api.nvim_win_call(preview_win, function()
						vim.cmd.normal({ args = { vim.keycode(key == "<C-f>" and "<C-d>" or "<C-u>") }, bang = true })
					end)
				end, { buf = buf, desc = "Scroll undo preview" })
			end
		end
		vim.keymap.set({ "n", "i" }, "<CR>", accept, { buf = buf })
		for _, key in ipairs({ "<C-n>", "<Down>", "<Tab>" }) do
			vim.keymap.set({ "n", "i" }, key, function()
				move(1)
			end, { buf = buf })
		end
		for _, key in ipairs({ "<C-p>", "<Up>", "<S-Tab>" }) do
			vim.keymap.set({ "n", "i" }, key, function()
				move(-1)
			end, { buf = buf })
		end
		vim.keymap.set({ "n", "i" }, "<C-q>", function()
			local items = state.matches
			state.close(true)
			show_results(items, title)
		end, { buf = buf, desc = "Send matches to quickfix" })
	end
	-- -------------------------------------
	-- Debounce input and refresh static or live search results
	-- -------------------------------------
	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		group = group,
		buf = query_buf,
		callback = function()
			state.generation = state.generation + 1
			local generation = state.generation
			if opts.live then
				if opts.cancel then
					opts.cancel()
				end
				state.items, state.matches, state.index = {}, {}, 1
				draw()
			end
			vim.defer_fn(function()
				if state.closed or generation ~= state.generation then
					return
				end
				if opts.live then
					opts.live(vim.api.nvim_buf_get_lines(query_buf, 0, 1, false)[1] or "", state, generation)
				else
					filter()
				end
			end, 120)
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		pattern = vim.tbl_map(tostring, state.windows),
		callback = function()
			state.close()
		end,
	})
	shared.active_picker = state
	state.set_items(opts.items or {})
	vim.cmd("startinsert")
	return state
end
-- =========================================
-- ====== PICKER: SELECT / LOCATIONS =====
-- =========================================
-- vim.ui.select와 LSP·진단 위치 목록을 공통 picker에 연결합니다.
-- 선택/취소 콜백은 한 번만 실행하고 원래 편집 창으로 복귀합니다.
vim.ui.select = function(items, opts, callback)
	opts = opts or {}
	local choices = {}
	for i, item in ipairs(items) do
		choices[i] = {
			label = opts.format_item and opts.format_item(item) or tostring(item),
			action = function()
				callback(item, i)
			end,
		}
	end
	shared.open_picker(opts.prompt or "Select", {
		items = choices,
		on_cancel = function()
			callback(nil, nil)
		end,
	})
end
function shared.location_picker(title, locations)
	local root = shared.project_root()
	local items = {}
	for _, item in ipairs(locations) do
		local filename = item.filename or (item.bufnr and vim.api.nvim_buf_get_name(item.bufnr)) or ""
		local label = filename:sub(1, #root + 1) == root .. "/" and filename:sub(#root + 2) or filename
		items[#items + 1] = {
			filename = filename,
			bufnr = item.bufnr,
			lnum = item.lnum,
			col = item.col,
			text = item.text,
			label = label .. ":" .. (item.lnum or 1) .. " " .. (item.text or ""),
		}
	end
	shared.open_picker(title, { items = items })
end
