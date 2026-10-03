local policy = require("buffer_policy")
local Snacks = require("snacks")

-- =========================================
-- =========== STICKY SCROLL =============
-- =========================================
-- <leader>Ts: 들여쓰기 기반 시작 줄 최대 8개 + 구분선. 파서/LSP 없이 동작합니다.
-- 위쪽 1,000줄/256 KiB까지만 탐색하며, 복잡한 여러 줄 구문은 해석하지 않습니다.
do
	local enabled, queued = false, false
	local popup, cache, rendered_config
	local numbers, numbers_config
	local number_hl = vim.api.nvim_create_namespace("pack-sticky-numbers")
	local function close()
		local windows = { popup, numbers }
		popup = nil
		numbers, numbers_config = nil, nil
		rendered_config = nil
		for _, win in pairs(windows) do
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
	end
	local function header_reader(buf, top, bottom)
		local first = math.max(1, top - 1000)
		local last = math.min(vim.api.nvim_buf_line_count(buf), bottom + 20)
		if vim.api.nvim_buf_get_offset(buf, last) - vim.api.nvim_buf_get_offset(buf, first - 1) > 256 * 1024 then
			return function()
				return {}
			end
		end
		local lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
		local python = vim.bo[buf].filetype == "python"
		local blocks = {
			def = true,
			class = true,
			["if"] = true,
			elif = true,
			["else"] = true,
			["for"] = true,
			["while"] = true,
			["try"] = true,
			except = true,
			finally = true,
			with = true,
			match = true,
			case = true,
		}
		local function text_at(line)
			local text = lines[line - first + 1]:match("^%s*(.-)%s*$")
			if text == "" or text:match("^#") or text:match("^//") or text:match("^/%*") or text:match("^%*") then
				return nil
			end
			return text
		end
		return function(top)
			local base = top
			while base <= last do
				local text = text_at(base)
				if text and not (text:match("^%)") and text:match("[:{]$")) then
					break
				end
				base = base + 1
			end
			if base > last then
				return {}
			end
			local indent, result, func = vim.fn.indent(base), {}, nil
			for line = top - 1, math.max(first, top - 1000), -1 do
				local text = text_at(line)
				if text then
					local level = vim.fn.indent(line)
					if level < indent then
						-- A closing signature line such as `):` is not its declaration.
						local keyword = text:gsub("^async%s+", ""):match("^([%a_]+)")
						if
							not text:match("^[%)%]%}]")
							and not text:match("^[{%[(;]+$")
							and (not python or blocks[keyword])
						then
							local entry = { text = lines[line - first + 1], lnum = line }
							table.insert(result, 1, entry)
							if
								not func
								and (keyword == "def" or text:match("^local%s+function%s") or keyword == "function")
							then
								func = entry
							end
							indent = level
							if indent == 0 then
								break
							end
						end
					end
				end
			end
			return result, func
		end
	end
	local function update()
		local win = vim.api.nvim_get_current_win()
		local buf = vim.api.nvim_win_get_buf(win)
		if
			not enabled
			or not policy.is_editor(win)
			or not policy.allows(buf)
			or vim.bo[buf].filetype == "netrw"
			or vim.fn.getcmdwintype() ~= ""
		then
			close()
			return
		end
		local view = vim.fn.winsaveview()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local screen_top = vim.fn.win_screenpos(win)[1] + vim.fn.getwininfo(win)[1].winbar
		local row = vim.fn.screenpos(win, cursor[1], cursor[2] + 1).row - screen_top
		local limit = math.min(8, math.floor(vim.api.nvim_win_get_height(win) / 3), row - 1)
		if limit < 1 then
			close()
			return
		end
		-- Map each possible overlay height to its first uncovered source line.
		-- Screen positions account for wrapped lines and closed folds.
		local targets, line = {}, view.topline
		local total = vim.api.nvim_buf_line_count(buf)
		for height = 1, limit + 1 do
			while line < total do
				local next_line = math.max(line, vim.fn.foldclosedend(line)) + 1
				if next_line > total then
					break
				end
				local next_row = vim.fn.screenpos(win, next_line, 1).row
				if next_row == 0 or next_row > screen_top + height then
					break
				end
				line = next_line
			end
			targets[height] = line
		end
		local key = {
			win,
			buf,
			vim.api.nvim_buf_get_changedtick(buf),
			view.topline,
			vim.bo[buf].tabstop,
			vim.bo[buf].vartabstop,
			vim.bo[buf].filetype,
			targets,
		}
		if not cache or not vim.deep_equal(cache.key, key) then
			local headers = header_reader(buf, view.topline, targets[#targets])
			local lines, func = headers(view.topline)
			local count = math.min(#lines, limit)
			-- Grow the context when the overlay hides more declarations. Keep the
			-- last complete context if its bottom reaches a closing/dedented line;
			-- shrinking here would cover a declaration again and cause oscillation.
			for _ = 1, limit do
				if count == 0 then
					break
				end
				local covered, enclosing = headers(targets[count + 1])
				if enclosing and func and enclosing.lnum ~= func.lnum and enclosing.lnum >= view.topline then
					-- Leave the next function declaration visible instead of covering
					-- it with context from the function that just ended.
					local boundary = vim.fn.screenpos(win, enclosing.lnum, 1).row - screen_top
					count = math.max(0, math.min(count, boundary - 1))
					break
				end
				if #covered < count then
					break
				end
				lines, func = covered, enclosing
				local next_count = math.min(#lines, limit)
				if next_count == count then
					break
				end
				count = next_count
			end
			local scopes = vim.list_slice(lines, #lines - count + 1)
			-- Preserve both the outermost scope and enclosing function when space
			-- permits; use the remaining rows for the nearest inner scopes.
			if count > 0 and not vim.tbl_contains(scopes, lines[1]) then
				scopes[1] = lines[1]
			end
			if count > 0 and func and not vim.tbl_contains(scopes, func) then
				scopes[math.min(2, count)] = func
			end
			cache = { key = key, scopes = scopes }
		end
		if #cache.scopes == 0 then
			close()
			return
		end
		-- Start after the actual number/sign/fold gutter, not at the window edge.
		local gutter = vim.fn.getwininfo(win)[1].textoff
		local width = vim.api.nvim_win_get_width(win) - gutter
		if width < 1 then
			close()
			return
		end
		local lines, labels = {}, {}
		for _, entry in ipairs(cache.scopes) do
			lines[#lines + 1] = entry.text
			local label = (vim.wo[win].number or vim.wo[win].relativenumber) and tostring(entry.lnum) or ""
			labels[#labels + 1] = string.rep(" ", math.max(0, gutter - #label - 1)) .. label .. " "
		end
		lines[#lines + 1] = string.rep("─", width)
		labels[#labels + 1] = string.rep("─", gutter)
		local config = {
			relative = "win",
			win = win,
			row = 0,
			col = gutter,
			width = width,
			height = #lines,
			focusable = false,
			style = "minimal",
			border = "none",
			zindex = 20,
		}
		if not popup or not vim.api.nvim_win_is_valid(popup) then
			local scratch = vim.api.nvim_create_buf(false, true)
			vim.bo[scratch].bufhidden = "wipe"
			popup = vim.api.nvim_open_win(scratch, false, config)
			vim.wo[popup][0].winhighlight = "Normal:Pmenu,EndOfBuffer:Pmenu"
			vim.wo[popup][0].wrap = false
		elseif not vim.deep_equal(rendered_config, config) then
			vim.api.nvim_win_set_config(popup, config)
		end
		rendered_config = config
		local scratch = vim.api.nvim_win_get_buf(popup)
		vim.bo[scratch].tabstop = vim.bo[buf].tabstop
		vim.bo[scratch].vartabstop = vim.bo[buf].vartabstop
		-- Use the source window's native indent guides, including <leader>Ti changes.
		for _, option in ipairs({ "list", "listchars" }) do
			if vim.wo[popup][option] ~= vim.wo[win][option] then
				vim.wo[popup][0][option] = vim.wo[win][option]
			end
		end
		-- Load bundled syntax only; avoid FileType hooks and LSPs in the popup.
		local syntax = vim.bo[buf].syntax ~= "" and vim.bo[buf].syntax or vim.bo[buf].filetype
		if vim.bo[scratch].syntax ~= syntax then
			vim.bo[scratch].syntax = syntax
		end
		if not vim.deep_equal(vim.api.nvim_buf_get_lines(scratch, 0, -1, false), lines) then
			vim.bo[scratch].modifiable = true
			vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
			vim.bo[scratch].modifiable = false
		end
		if vim.fn.getwininfo(popup)[1].leftcol ~= view.leftcol then
			vim.wo[popup][0].virtualedit = "all"
			vim.api.nvim_win_call(popup, function()
				vim.cmd("normal! " .. (view.leftcol + 1) .. "|")
				vim.fn.winrestview({ topline = 1, leftcol = view.leftcol })
			end)
		end
		-- Cover the source gutter too: its visible row numbers belong to different lines.
		if gutter > 0 then
			local layout = vim.tbl_extend("force", config, { col = 0, width = gutter })
			if not numbers or not vim.api.nvim_win_is_valid(numbers) then
				local buf = vim.api.nvim_create_buf(false, true)
				vim.bo[buf].bufhidden = "wipe"
				numbers = vim.api.nvim_open_win(buf, false, layout)
				vim.wo[numbers][0].winhighlight = "Normal:Pmenu,EndOfBuffer:Pmenu,LineNr:LineNr"
			elseif not vim.deep_equal(numbers_config, layout) then
				vim.api.nvim_win_set_config(numbers, layout)
			end
			numbers_config = layout
			local buf = vim.api.nvim_win_get_buf(numbers)
			if not vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), labels) then
				vim.bo[buf].modifiable = true
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, labels)
				vim.bo[buf].modifiable = false
				vim.api.nvim_buf_clear_namespace(buf, number_hl, 0, -1)
				for row = 0, #labels - 2 do
					vim.api.nvim_buf_set_extmark(
						buf,
						number_hl,
						row,
						0,
						{ end_col = #labels[row + 1], hl_group = "LineNr" }
					)
				end
			end
		elseif numbers then
			if vim.api.nvim_win_is_valid(numbers) then
				vim.api.nvim_win_close(numbers, true)
			end
			numbers, numbers_config = nil, nil
		end
	end
	local function queue()
		if not enabled or queued then
			return
		end
		queued = true
		vim.schedule(function()
			queued = false
			update()
		end)
	end
	local group = vim.api.nvim_create_augroup("pack-sticky-scroll", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "PackBufferRestricted",
		callback = function(args)
			if cache and cache.key[2] == args.data.buf then
				close()
				cache = nil
			end
		end,
	})
	vim.api.nvim_create_autocmd({
		"VimEnter",
		"BufEnter",
		"WinEnter",
		"WinScrolled",
		"VimResized",
		"CursorMoved",
		"CursorMovedI",
		"TextChanged",
		"TextChangedI",
		"InsertLeave",
		"FileType",
	}, {
		group = group,
		callback = queue,
	})
	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = {
			"number",
			"relativenumber",
			"numberwidth",
			"signcolumn",
			"foldcolumn",
			"statuscolumn",
			"list",
			"listchars",
			"tabstop",
			"vartabstop",
			"shiftwidth",
			"wrap",
			"winbar",
			"previewwindow",
		},
		callback = function()
			if vim.api.nvim_win_get_config(0).relative == "" then
				queue()
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "TabLeave" }, { group = group, callback = close })
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			if cache and tonumber(args.match) == cache.key[1] then
				close()
				cache = nil
			end
		end,
	})
	Snacks.toggle({
		name = "Sticky scroll",
		get = function()
			return enabled
		end,
		set = function(state)
			enabled = state
			if enabled then
				queue()
			else
				close()
			end
		end,
	}):map("<leader>Ts")
end
