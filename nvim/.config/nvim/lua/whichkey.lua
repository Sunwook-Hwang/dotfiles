-- =========================================
-- ========= LEADER KEY GUIDE ============
-- =========================================
-- Normal mode only: inspect real mappings, then replay the selected shortcut.
-- Complete shortcuts already in typeahead use Neovim's normal mapping path.
do
	local leader = vim.keycode("<leader>")
	local groups = {
		s = "Search",
		S = "Substitute",
		b = "Buffer",
		T = "Toggle",
		l = "LSP & Diagnostic",
		g = "Git",
		p = "Project",
		n = "File tree",
		P = "Peerpad",
	}
	local active
	local function mappings(buf)
		local found = {}
		for _, list in ipairs({ vim.api.nvim_get_keymap("n"), vim.api.nvim_buf_get_keymap(buf, "n") }) do
			for _, item in ipairs(list) do
				local lhs = item.lhsraw or vim.api.nvim_replace_termcodes(item.lhs, true, true, true)
				if lhs:sub(1, #leader) == leader and #lhs > #leader then
					found[lhs] = item
				end
			end
		end
		return found
	end
	local function guide()
		local source_win, source_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
		local count, register = vim.v.count, vim.v.register
		local prefix, popup = leader, nil
		local cancelled = false
		local function close()
			local win = popup
			popup = nil
			if win and vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
		local function choices(items)
			local next_keys = {}
			for lhs, item in pairs(items) do
				if lhs:sub(1, #prefix) == prefix and #lhs > #prefix then
					local rest = vim.fn.keytrans(lhs:sub(#prefix + 1))
					local key = rest:match("^<[^>]+>") or vim.fn.strcharpart(rest, 0, 1)
					if rest == key then
						next_keys[key] = item.desc or item.lhs
					elseif not next_keys[key] then
						next_keys[key] = "+ " .. (groups[prefix:sub(#leader + 1) .. key] or key)
					end
				end
			end
			local result = {}
			for _, key in ipairs(vim.fn.sort(vim.tbl_keys(next_keys))) do
				result[#result + 1] = key .. "  " .. next_keys[key]
			end
			return result
		end
		local function draw(entries)
			entries = entries or choices(mappings(source_buf))
			local width = math.max(1, math.min(120, vim.o.columns - 4))
			local columns = math.max(1, math.min(3, math.floor(width / 32)))
			local cell = math.floor(width / columns)
			local rows = math.max(1, math.ceil(#entries / columns))
			local height = math.min(rows, math.max(1, vim.o.lines - 6))
			local lines = {}
			for row = 1, height do
				local cells = {}
				for col = 1, columns do
					local text = entries[(col - 1) * rows + row] or ""
					-- Bound by screen cells, including non-ASCII descriptions.
					local limit = math.max(1, cell - 2)
					if vim.fn.strdisplaywidth(text) > limit then
						text = vim.fn.strcharpart(text, 0, limit - 1)
						while vim.fn.strdisplaywidth(text) > limit - 1 do
							text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
						end
						text = text .. "…"
					end
					cells[#cells + 1] = text .. string.rep(" ", math.max(0, cell - vim.fn.strdisplaywidth(text)))
				end
				lines[#lines + 1] = table.concat(cells)
			end
			local config = {
				relative = "editor",
				row = math.max(0, vim.o.lines - height - vim.o.cmdheight - 3),
				col = math.max(0, math.floor((vim.o.columns - width) / 2)),
				width = width,
				height = height,
				style = "minimal",
				border = "rounded",
				focusable = false,
				zindex = 80,
				title = " <leader>" .. vim.fn.keytrans(prefix:sub(#leader + 1)) .. " · Esc: cancel ",
			}
			if not popup or not vim.api.nvim_win_is_valid(popup) then
				local buf = vim.api.nvim_create_buf(false, true)
				vim.bo[buf].bufhidden = "wipe"
				popup = vim.api.nvim_open_win(buf, false, config)
			else
				vim.api.nvim_win_set_config(popup, config)
			end
			local buf = vim.api.nvim_win_get_buf(popup)
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			vim.bo[buf].modifiable = false
			vim.cmd("redraw")
		end
		active = {
			draw = draw,
			cancel = function()
				cancelled = true
				close()
				-- Wake getcharstr if an external action changes the editing context.
				vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "ni", false)
			end,
		}
		local ok, err = xpcall(function()
			while not cancelled do
				local items = mappings(source_buf)
				if items[prefix] then
					close()
					local lead = register ~= '"' and ('"' .. register) or ""
					lead = lead .. (count > 0 and tostring(count) or "")
					-- Remap through the original callback/RHS, without recording it twice.
					vim.api.nvim_feedkeys(lead .. prefix, "mi", false)
					return
				end
				local entries = choices(items)
				if #entries == 0 then
					return
				end
				if vim.fn.getcharstr(1) == "" then
					draw(entries)
				end
				local read, key = pcall(vim.fn.getcharstr, -1, { cursor = "keep" })
				if not read or key == vim.keycode("<Esc>") or key == "\003" or cancelled then
					return
				end
				if vim.api.nvim_get_current_win() ~= source_win or vim.api.nvim_get_current_buf() ~= source_buf then
					return
				end
				prefix = prefix .. key
			end
		end, debug.traceback)
		active = nil
		close()
		if not ok then
			vim.notify(err, vim.log.levels.ERROR)
		end
	end
	vim.keymap.set("n", "<leader>", guide, { nowait = true, silent = true, desc = "Leader key guide" })
	local group = vim.api.nvim_create_augroup("nopack-leader-guide", { clear = true })
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "TabLeave" }, {
		group = group,
		callback = function()
			if active then
				active.cancel()
			end
		end,
	})
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			if active then
				active.draw()
			end
		end,
	})
end
