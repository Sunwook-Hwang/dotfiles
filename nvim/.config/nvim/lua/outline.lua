local policy = require("buffer_policy")
local shared = require("state")
local outline_ns = vim.api.nvim_create_namespace("nopack-outline-highlights")
local function name_highlight(kind)
	kind = kind:lower()
	if kind == "function" or kind == "method" or kind == "constructor" then
		return "Function"
	end
	if kind == "class" or kind == "struct" or kind == "interface" or kind == "enum" then
		return "Type"
	end
	return "Identifier"
end

-- =========================================
-- ========== CODE OUTLINE / LSP + CTAGS ==========
-- =========================================
-- <leader>o: toggle the current file's function/class hierarchy in a right sidebar.
-- Enter: jump to the location; r: refresh; q/<leader>o: close; Ctrl-h/j/k/l: navigate windows.
-- Moving the sidebar cursor previews the symbol location in the editor without changing focus.
-- Moving the editor cursor also updates the sidebar selection using cached symbol ranges.
-- While open, refresh only on file switches, saves or LSP attachment; do not request on every keystroke.
local function follow_source(state)
	if
		not vim.api.nvim_win_is_valid(state.win)
		or vim.api.nvim_win_get_buf(state.win) ~= state.buf
		or not policy.is_editor(state.source_win)
		or vim.api.nvim_win_get_buf(state.source_win) ~= state.source
		or not policy.allows(state.source)
		or not state.source_context
		or not policy.source_unchanged(state.source_context)
	then
		return
	end
	local cursor = vim.api.nvim_win_get_cursor(state.source_win)
	local row, character = cursor[1] - 1, nil
	local selected, enclosing, nearest
	local function before(a, b)
		return a.line < b.line or (a.line == b.line and a.character < b.character)
	end
	for i, item in ipairs(state.items) do
		if item.range then
			if not character then
				local line = vim.api.nvim_buf_get_lines(state.source, row, row + 1, false)[1] or ""
				character = vim.str_utfindex(line, state.encoding or "utf-16", cursor[2], false)
			end
			local position, range = { line = row, character = character }, item.range
			if
				not before(position, range.start)
				and before(position, range["end"])
				and (
					not enclosing
					or (not before(range.start, enclosing.start) and not before(enclosing["end"], range["end"]))
				)
			then
				selected, enclosing = i, range
			end
		elseif item.lnum and item.lnum <= cursor[1] and (not nearest or item.lnum > nearest) then
			-- Ctags supplies declaration lines, not enclosing ranges.
			selected, nearest = i, item.lnum
		end
	end
	if selected then
		state.selected_row = selected
		if vim.api.nvim_win_get_cursor(state.win)[1] ~= selected then
			vim.api.nvim_win_set_cursor(state.win, { selected, 0 })
		end
	end
end
local function outline_text(state, lines)
	if not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(state.buf, outline_ns, 0, -1)
	for i, item in ipairs(state.items) do
		if item.label == lines[i] then
			for _, span in ipairs(item.highlights or {}) do
				vim.api.nvim_buf_set_extmark(state.buf, outline_ns, i - 1, span[1], {
					end_col = span[2],
					hl_group = span[3],
				})
			end
		end
	end
	follow_source(state)
end
shared.cancel_outline = function(state)
	state.version = state.version + 1
	state.refresh_pending = nil
	if state.cancel then
		state.cancel()
		state.cancel = nil
	end
end
vim.api.nvim_create_autocmd("User", {
	pattern = "NopackCancel",
	callback = function()
		if shared.outline then
			shared.cancel_outline(shared.outline)
		end
	end,
})
vim.api.nvim_create_autocmd("BufUnload", {
	callback = function(args)
		local state = shared.outline
		if state and state.source == args.buf then
			shared.cancel_outline(state)
			state.items = {}
			outline_text(state, { "Source buffer closed" })
		end
	end,
})
local function ctags_outline(state)
	local version, buf = state.version, state.source
	-- Ctags describes the saved file, so unsaved edits cannot drive cursor tracking.
	state.source_context = not vim.bo[buf].modified and policy.source_context(buf) or nil
	state.items = {}
	local root, file = shared.tag_context(buf)
	if not root then
		outline_text(state, { "Ctags unavailable or file exceeds size limits" })
		return
	end
	if file:find("[\r\n]") then
		return
	end
	local stat = vim.uv.fs_stat(file)
	local stamp = stat and (stat.size .. ":" .. stat.mtime.sec .. ":" .. stat.mtime.nsec)
	if stamp and state.ctags_file == file and state.ctags_stamp == stamp then
		state.items = state.ctags_items
		outline_text(state, state.ctags_lines)
		return
	end
	outline_text(state, { "Indexing saved file..." })
	shared.build_tags(root, false, { file }, function(output)
		if shared.outline ~= state or state.version ~= version or not policy.allows(buf) then
			return
		end
		local items = {}
		for _, line in ipairs(shared.records(output, "\n")) do
			if not line:match("^!_TAG_") and shared.tag_filename(line) == file then
				local name = line:match("^([^\t]+)")
				local row = tonumber(line:match("\tline:(%d+)"))
				local kind = line:match(';"\t([^\t]+)') or "symbol"
				local kind_label = kind:gsub("^%l", string.upper)
				local scope = ""
				for _, field in ipairs({ "class", "struct", "namespace", "union", "enum", "function", "scope" }) do
					scope = line:match("\t" .. field .. ":([^\t]+)") or scope
				end
				if row then
					local depth = scope == "" and 0 or #vim.split(scope:gsub("::", "."), ".", { plain = true })
					items[#items + 1] = {
						lnum = row,
						label = string.rep("  ", depth)
							.. kind_label
							.. " "
							.. name
							.. (scope == "" and "" or " (" .. scope .. ")"),
						highlights = {
							{ depth * 2, depth * 2 + #kind_label, "Comment" },
							{ depth * 2 + #kind_label + 1, depth * 2 + #kind_label + 1 + #name, name_highlight(kind) },
						},
					}
				end
			end
		end
		table.sort(items, function(a, b)
			return a.lnum < b.lnum
		end)
		state.items = items
		local lines = #items > 0 and vim.tbl_map(function(item)
			return item.label
		end, items) or { "No symbols in saved file" }
		state.ctags_file, state.ctags_stamp = file, stamp
		state.ctags_items, state.ctags_lines = items, lines
		outline_text(state, lines)
	end, function(_, cancelled)
		if shared.outline == state and state.version == version then
			outline_text(
				state,
				{ cancelled and "Ctags indexing cancelled" or "Ctags indexing failed", "Press r to retry" }
			)
		end
	end)
end
local function refresh_outline(state)
	shared.cancel_outline(state)
	local version, buf = state.version, state.source
	state.items = {}
	state.source_context = nil
	if not policy.allows(buf) then
		outline_text(state, { "Source buffer closed" })
		return
	end
	local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentSymbol" })
	if #clients == 0 then
		ctags_outline(state)
		return
	end
	-- Use one provider to avoid duplicate symbols when several LSP clients attach.
	table.sort(clients, function(a, b)
		return a.id < b.id
	end)
	local client = clients[1]
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	local context = policy.source_context(buf)
	local completed = false
	outline_text(state, { "Loading symbols..." })
	local ok, request = client:request("textDocument/documentSymbol", {
		textDocument = { uri = vim.uri_from_bufnr(buf) },
	}, function(err, symbols)
		completed = true
		vim.schedule(function()
			if shared.outline ~= state or state.version ~= version then
				return
			end
			state.cancel = nil
			if not policy.allows(buf) then
				return
			end
			if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
				outline_text(state, { "File changed; save or press r" })
				return
			end
			if err or symbols == nil or symbols == vim.NIL or #symbols == 0 then
				ctags_outline(state)
				return
			end
			local lines, items = {}, {}
			local function collect(nodes, depth)
				for _, symbol in ipairs(nodes) do
					local location = symbol.location
						or { uri = vim.uri_from_bufnr(buf), range = symbol.selectionRange or symbol.range }
					local kind = vim.lsp.protocol.SymbolKind[symbol.kind] or "Symbol"
					lines[#lines + 1] = string.rep("  ", depth) .. kind .. " " .. symbol.name:gsub("[%c]", " ")
					items[#items + 1] = {
						location = location,
						range = symbol.range or location.range,
						label = lines[#lines],
						highlights = {
							{ depth * 2, depth * 2 + #kind, "Comment" },
							{ depth * 2 + #kind + 1, #lines[#lines], name_highlight(kind) },
						},
					}
					if symbol.children then
						collect(symbol.children, depth + 1)
					end
				end
			end
			collect(symbols ~= vim.NIL and symbols or {}, 0)
			state.items, state.encoding = items, client.offset_encoding
			state.source_context = context
			outline_text(state, #lines > 0 and lines or { "No symbols in this file" })
		end)
	end, buf)
	if not ok then
		ctags_outline(state)
		return
	end
	state.cancel = function()
		if not completed then
			client:cancel_request(request)
		end
	end
	vim.defer_fn(function()
		if shared.outline == state and state.version == version and state.cancel and not completed then
			shared.cancel_outline(state)
			ctags_outline(state)
		end
	end, 5000)
end
shared.map("n", "<leader>o", function()
	if shared.outline then
		vim.api.nvim_win_close(shared.outline.win, true)
		return
	end
	shared.focus_editor()
	if not policy.allows(0) or vim.api.nvim_buf_get_name(0) == "" then
		vim.notify("Open a code file to view its outline")
		return
	end
	local state = {
		source = vim.api.nvim_get_current_buf(),
		source_win = vim.api.nvim_get_current_win(),
		version = 0,
		items = {},
	}
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].filetype = "nopack_outline"
	state.win = vim.api.nvim_open_win(state.buf, true, {
		split = "right",
		win = state.source_win,
		width = shared.sidebar_width(),
	})
	shared.outline = state
	shared.fix_sidebar_width(state.win)
	-- Buffer-local window options must not become defaults for files opened here.
	vim.wo[state.win][0].number = false
	vim.wo[state.win][0].relativenumber = false
	vim.wo[state.win][0].signcolumn = "no"
	vim.wo[state.win][0].wrap = false
	vim.wo[state.win][0].cursorline = true
	vim.wo[state.win][0].cursorlineopt = "line"
	vim.wo[state.win][0].cursorcolumn = false
	vim.wo[state.win][0].winbar = " Outline: "
		.. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(state.source), ":t"):gsub("%%", "%%%%")
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(state.win, true)
	end, { buf = state.buf, desc = "Close outline" })
	vim.keymap.set("n", "r", function()
		refresh_outline(state)
	end, { buf = state.buf, desc = "Refresh outline" })
	vim.api.nvim_create_autocmd("CursorMoved", {
		buf = state.buf,
		callback = function()
			if
				shared.outline ~= state
				or vim.api.nvim_get_current_win() ~= state.win
				or not policy.allows(state.source)
				or not policy.is_editor(state.source_win)
				or vim.api.nvim_win_get_buf(state.source_win) ~= state.source
				or not state.source_context
				or not policy.source_unchanged(state.source_context)
			then
				return
			end
			local row_index = vim.api.nvim_win_get_cursor(state.win)[1]
			if row_index == state.selected_row then
				return
			end
			state.selected_row = row_index
			local item = state.items[row_index]
			if not item then
				return
			end
			local row, col = item.lnum, 0
			if item.location then
				if vim.fn.bufnr(vim.uri_to_fname(item.location.uri)) ~= state.source then
					return
				end
				local start = item.location.range.start
				row = start.line + 1
				local line = vim.api.nvim_buf_get_lines(state.source, row - 1, row, false)[1] or ""
				col = vim.str_byteindex(line, state.encoding, start.character, false)
			end
			local position = { math.min(row, vim.api.nvim_buf_line_count(state.source)), col }
			if not vim.deep_equal(vim.api.nvim_win_get_cursor(state.source_win), position) then
				vim.api.nvim_win_set_cursor(state.source_win, position)
				vim.api.nvim_win_call(state.source_win, function()
					vim.cmd("normal! zvzz")
				end)
			end
		end,
	})
	vim.keymap.set("n", "<CR>", function()
		if not state.source_context or not policy.source_unchanged(state.source_context) then
			vim.notify("Outline is out of date; save the file or press r to refresh")
			return
		end
		local item = state.items[vim.api.nvim_win_get_cursor(state.win)[1]]
		if not item then
			return
		end
		local source = state.source
		if policy.is_editor(state.source_win) then
			vim.api.nvim_set_current_win(state.source_win)
		else
			shared.focus_editor()
		end
		if item.location then
			vim.lsp.util.show_document(item.location, state.encoding, { focus = true })
		elseif vim.api.nvim_buf_is_valid(source) then
			vim.cmd("normal! m'")
			vim.api.nvim_win_set_buf(0, source)
			vim.api.nvim_win_set_cursor(0, { math.min(item.lnum, vim.api.nvim_buf_line_count(source)), 0 })
		end
		vim.cmd("normal! zvzz")
	end, { buf = state.buf, desc = "Jump to symbol" })
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(state.win),
		once = true,
		callback = function()
			shared.cancel_outline(state)
			if shared.outline == state then
				shared.outline = nil
			end
		end,
	})
	refresh_outline(state)
end, "Toggle code outline")
vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter" }, {
	callback = function(args)
		local state = shared.outline
		if state and args.buf == state.source and policy.is_editor(0) then
			state.source_win = vim.api.nvim_get_current_win()
			follow_source(state)
		end
	end,
})
vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "BufFilePost", "FileType", "LspAttach", "LspDetach" }, {
	callback = function(args)
		local state = shared.outline
		-- Reusing the sidebar window ends its outline, even if a split still shows the old buffer.
		if state and vim.api.nvim_win_get_buf(state.win) ~= state.buf then
			shared.cancel_outline(state)
			shared.outline = nil
			return
		end
		if state and args.buf == state.source and (args.event == "BufFilePost" or args.event == "FileType") then
			shared.cancel_outline(state)
			state.items = {}
			vim.wo[state.win][0].winbar = " Outline: "
				.. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(args.buf), ":t"):gsub("%%", "%%%%")
			if not policy.allows(args.buf) then
				outline_text(state, { "Source buffer unavailable" })
				return
			end
		end
		if
			not state
			or not policy.allows(args.buf)
			or vim.api.nvim_win_get_tabpage(state.win) ~= vim.api.nvim_get_current_tabpage()
		then
			return
		end
		if args.event == "BufEnter" then
			if not policy.is_editor(0) then
				return
			end
			local same_source = state.source == args.buf
			state.source, state.source_win = args.buf, vim.api.nvim_get_current_win()
			if same_source then
				return
			end
			vim.wo[state.win][0].winbar = " Outline: "
				.. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(args.buf), ":t"):gsub("%%", "%%%%")
		end
		if args.buf == state.source and not state.refresh_pending then
			local pending = {}
			state.refresh_pending = pending
			vim.schedule(function()
				if state.refresh_pending ~= pending then
					return
				end
				state.refresh_pending = nil
				if shared.outline == state then
					refresh_outline(state)
				end
			end)
		end
	end,
})

vim.api.nvim_create_autocmd("User", {
	pattern = "NopackBufferRestricted",
	callback = function(args)
		local state = shared.outline
		if state and state.source == args.data.buf then
			shared.cancel_outline(state)
			state.items = {}
			outline_text(state, { "Large-file protection is active" })
		end
	end,
})
