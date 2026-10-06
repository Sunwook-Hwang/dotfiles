local policy = require("buffer_policy")
local Snacks = require("snacks")

-- -------------------------------------
-- Buffers: native tabline and navigation (from nvim/init.lua)
-- -------------------------------------
do
	local map = function(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
	end
	local function focus_editor()
		if policy.is_editor(0) then
			return
		end
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if policy.is_editor(win) then
				vim.api.nvim_set_current_win(win)
				return
			end
		end
		vim.cmd("botright vnew")
	end

	local function select_buffer(buf)
		focus_editor()
		vim.api.nvim_set_current_buf(buf)
	end

	-- =========================================
	-- ========== BUFFERS / TABLINE ==========
	-- =========================================
	-- Barbar 대체: 표시 순서를 이동·번호 선택·좌우 닫기에서 함께 사용합니다.
	-- Shift-h/l, [b/]b: 이동; Alt-1..9: 선택; Space bj/bk: 재배열; bD/bL: 정렬.
	-- Space c: 강제 닫기; bw: 미저장 보호; bm/be/bh/bl: 다른·왼쪽·오른쪽 버퍼 정리.
	local buffer_order = {}
	local tabline_cache
	local function buffer_highlights()
		local selected = vim.api.nvim_get_hl(0, { name = "TabLineSel", link = false })
		local inactive = { link = "TabLine" }
		local fill = { link = "TabLineFill" }
		if (vim.g.colors_name or ""):match("^ayu") then
			local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
			selected = { bg = normal.fg, fg = normal.bg, bold = true }
			inactive = { bg = normal.bg, fg = normal.fg }
			fill = { link = "PackBufferInactive" }
		elseif selected.bg == nil and not selected.reverse then
			local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
			local accent = vim.api.nvim_get_hl(0, { name = "Special", link = false })
			-- Themes with bold-only selected tabs need an explicit, contrasting surface.
			selected = { bg = accent.fg or normal.fg, fg = normal.bg, bold = true }
			local tab = vim.api.nvim_get_hl(0, { name = "TabLine", link = false })
			inactive = { bg = tab.bg or normal.bg, fg = tab.fg or normal.fg }
			fill = { link = "PackBufferInactive" }
		end
		vim.api.nvim_set_hl(0, "PackBufferCurrent", selected)
		vim.api.nvim_set_hl(0, "PackBufferInactive", inactive)
		vim.api.nvim_set_hl(0, "PackBufferFill", fill)
	end
	buffer_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", { callback = buffer_highlights })
	local function buffers()
		local seen = {}
		buffer_order = vim.tbl_filter(function(buf)
			local keep = vim.api.nvim_buf_is_valid(buf)
				and vim.bo[buf].buflisted
				and (policy.is_source(buf) or vim.bo[buf].buftype == "terminal")
			if keep then
				seen[buf] = true
			end
			return keep
		end, buffer_order)
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if
				not seen[buf]
				and vim.bo[buf].buflisted
				and (policy.is_source(buf) or vim.bo[buf].buftype == "terminal")
			then
				buffer_order[#buffer_order + 1] = buf
			end
		end
		return buffer_order
	end
	local function buffer_index(buf, items)
		for i, candidate in ipairs(items or buffers()) do
			if candidate == buf then
				return i
			end
		end
		return 1
	end
	-- Listed buffers in the top bar; numbers match Alt-1..8 (Alt-9 = last).
	function _G.NativeTabline()
		if tabline_cache then
			return tabline_cache
		end
		local items = {}
		for i, b in ipairs(buffers()) do
			local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t")
			if name == "" then
				name = "[No Name]"
			end
			local hl = b == vim.api.nvim_get_current_buf() and "%#PackBufferCurrent#" or "%#PackBufferInactive#"
			items[#items + 1] = hl
				.. " "
				.. i
				.. ":"
				.. name:gsub("%%", "%%%%")
				.. (vim.bo[b].modified and " + " or " ")
		end
		tabline_cache = table.concat(items) .. "%#PackBufferFill#"
		return tabline_cache
	end
	vim.opt.tabline = "%!v:lua.NativeTabline()"
	local function invalidate_tabline()
		tabline_cache = nil
	end
	local tabline_events = { "BufAdd", "BufDelete", "BufEnter", "BufFilePost", "FileType", "TermOpen" }
	if vim.fn.has("nvim-0.13") == 0 then
		-- In 0.12, OptionSet alone does not cover modified changes caused by editing.
		tabline_events[#tabline_events + 1] = "BufModifiedSet"
	end
	vim.api.nvim_create_autocmd(tabline_events, {
		callback = invalidate_tabline,
	})
	vim.api.nvim_create_autocmd("OptionSet", {
		pattern = { "buflisted", "buftype", "modified" },
		callback = invalidate_tabline,
	})

	-- =========================================
	-- ======= BUFFER PICKER / KEYMAPS =======
	-- =========================================
	-- Use the existing selection UI for the same ordered buffer list.
	local function pick_buffer()
		focus_editor()
		local order = {}
		for index, buf in ipairs(buffers()) do
			order[buf] = index
		end
		Snacks.picker.buffers({
			sort_lastused = false,
			sort = { fields = { "score:desc", "order" } },
			transform = function(item)
				item.order = order[item.buf]
				return item.order ~= nil
			end,
		})
	end
	for key, command in pairs({ ["<S-l>"] = "bnext", ["<S-h>"] = "bprevious", ["]b"] = "bnext", ["[b"] = "bprevious" }) do
		map("n", key, function()
			focus_editor()
			local items = buffers()
			local index = buffer_index(vim.api.nvim_get_current_buf(), items)
			local delta = command == "bnext" and 1 or -1
			if #items > 0 then
				select_buffer(items[(index + delta - 1) % #items + 1])
			end
		end, command == "bnext" and "Next buffer" or "Previous buffer")
	end
	for key, delta in pairs({ bj = -1, bk = 1 }) do
		map("n", "<leader>" .. key, function()
			focus_editor()
			local index = buffer_index(vim.api.nvim_get_current_buf())
			if buffer_order[index] ~= vim.api.nvim_get_current_buf() then
				return
			end
			local target = math.max(1, math.min(#buffer_order, index + delta))
			local buf = table.remove(buffer_order, index)
			table.insert(buffer_order, target, buf)
			invalidate_tabline()
			vim.cmd("redrawtabline")
		end, "Move buffer in displayed order")
	end
	for key, field in pairs({ bD = "directory", bL = "language" }) do
		map("n", "<leader>" .. key, function()
			buffers()
			table.sort(buffer_order, function(a, b)
				local left = field == "directory" and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(a), ":h")
					or vim.bo[a].filetype
				local right = field == "directory" and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":h")
					or vim.bo[b].filetype
				return left == right and a < b or left < right
			end)
			invalidate_tabline()
			vim.cmd("redrawtabline")
		end, "Order buffers by " .. field)
	end
	local function close_current_buffer(force)
		local is_terminal = vim.bo.buftype == "terminal"
		if vim.bo.modified and not is_terminal and not force then
			vim.notify("Unsaved changes: save the buffer before closing")
			return
		end
		Snacks.bufdelete({ force = force or is_terminal, wipe = true })
	end
	map("n", "<leader>c", function()
		close_current_buffer(true)
	end, "Force wipe current buffer (original binding)")
	map("n", "<leader>bw", function()
		close_current_buffer(false)
	end, "Wipe buffer (protect unsaved files)")
	map("n", "<leader>bp", pick_buffer, "Pick buffer")
	map("n", "<leader>sb", pick_buffer, "Search buffers")
	for i = 1, 9 do
		map("n", "<A-" .. i .. ">", function()
			local items = buffers()
			local b = items[i == 9 and #items or i]
			if b then
				select_buffer(b)
			end
		end, "Go to buffer " .. i)
	end
	for key, side in pairs({ be = "all", bm = "all", bh = "left", bl = "right" }) do
		map("n", "<leader>" .. key, function()
			focus_editor()
			local current = vim.api.nvim_get_current_buf()
			local items = buffers()
			local index = buffer_index(current, items)
			local targets = {}
			for position, b in ipairs(items) do
				if
					b ~= current
					and (
						side == "all"
						or (side == "left" and position < index)
						or (side == "right" and position > index)
					)
				then
					targets[b] = true
				end
			end
			Snacks.bufdelete({
				wipe = true,
				force = true,
				filter = function(buf)
					return targets[buf] and (vim.bo[buf].buftype == "terminal" or not vim.bo[buf].modified)
				end,
			})
		end, "Close " .. side .. " buffers (keep modified)")
	end
end
