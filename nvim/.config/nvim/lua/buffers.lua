local policy = require("buffer_policy")
local shared = require("state")

-- =========================================
-- ========== BUFFERS / TABLINE ==========
-- =========================================
-- Native Barbar replacement: navigation, numbered selection and side closing share the displayed order.
-- Shift-h/l, [b/]b: navigate; Alt-1..9: select; <leader>bj/bk: reorder; bD/bL: sort.
-- <leader>c: force close; bw: protect unsaved changes; bm/be/bh/bl: close other, left or right buffers.
local buffer_order = {}
local tabline_cache
local function buffer_highlights()
	local selected = vim.api.nvim_get_hl(0, { name = "TabLineSel", link = false })
	local inactive = { link = "TabLine" }
	local fill = { link = "TabLineFill" }
	if (vim.g.colors_name or ""):match("^ayu") then
		local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
		-- Prevent TabLine's reverse attribute from combining with these colors.
		selected = { bg = normal.fg, fg = normal.bg, bold = true, nocombine = true, cterm = { nocombine = true } }
		inactive = { bg = normal.bg, fg = normal.fg, nocombine = true, cterm = { nocombine = true } }
		fill = { link = "NopackBufferInactive" }
	elseif selected.bg == nil and not selected.reverse then
		local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
		local accent = vim.api.nvim_get_hl(0, { name = "Special", link = false })
		-- Themes with bold-only selected tabs need an explicit, contrasting surface.
		selected = { bg = accent.fg or normal.fg, fg = normal.bg, bold = true }
		local tab = vim.api.nvim_get_hl(0, { name = "TabLine", link = false })
		inactive = { bg = tab.bg or normal.bg, fg = tab.fg or normal.fg }
		fill = { link = "NopackBufferInactive" }
	end
	vim.api.nvim_set_hl(0, "NopackBufferCurrent", selected)
	vim.api.nvim_set_hl(0, "NopackBufferInactive", inactive)
	vim.api.nvim_set_hl(0, "NopackBufferFill", fill)
end
buffer_highlights()
vim.api.nvim_create_autocmd("ColorScheme", { callback = buffer_highlights })
function shared.buffers()
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
		if not seen[buf] and vim.bo[buf].buflisted and (policy.is_source(buf) or vim.bo[buf].buftype == "terminal") then
			buffer_order[#buffer_order + 1] = buf
		end
	end
	return buffer_order
end
local function buffer_index(buf, items)
	for i, candidate in ipairs(items or shared.buffers()) do
		if candidate == buf then
			return i
		end
	end
	return 1
end
-- Listed buffers in the top bar; numbers match Alt-1..8 (Alt-9 = last).
function _G.NopackTablineClick(buf, _, button)
	if button == "l" and vim.api.nvim_buf_is_valid(buf) then
		shared.select_buffer(buf)
	end
end

function _G.NopackTabline()
	if tabline_cache then
		return tabline_cache
	end
	local items = {}
	for i, b in ipairs(shared.buffers()) do
		local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t")
		if name == "" then
			name = "[No Name]"
		end
		local hl = b == vim.api.nvim_get_current_buf() and "%#NopackBufferCurrent#" or "%#NopackBufferInactive#"
		items[#items + 1] = hl
			.. "%"
			.. b
			.. "@v:lua.NopackTablineClick@"
			.. " "
			.. i
			.. ":"
			.. name:gsub("%%", "%%%%")
			.. (vim.bo[b].modified and " + " or " ")
			.. "%T"
	end
	tabline_cache = table.concat(items) .. "%#NopackBufferFill#"
	return tabline_cache
end
vim.opt.tabline = "%!v:lua.NopackTabline()"
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
-- <leader>bp/sb use the shared picker from the pickers module.
local function pick_buffer()
	local items = {}
	for _, b in ipairs(shared.buffers()) do
		local name = vim.api.nvim_buf_get_name(b)
		items[#items + 1] = {
			bufnr = b,
			filename = name ~= "" and name or nil,
			label = b .. ": " .. (name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]"),
		}
	end
	shared.open_picker("Buffers", { items = items })
end
for key, command in pairs({ ["<S-l>"] = "bnext", ["<S-h>"] = "bprevious", ["]b"] = "bnext", ["[b"] = "bprevious" }) do
	shared.map("n", key, function()
		shared.focus_editor()
		local items = shared.buffers()
		local index = buffer_index(vim.api.nvim_get_current_buf(), items)
		local delta = command == "bnext" and 1 or -1
		if #items > 0 then
			shared.select_buffer(items[(index + delta - 1) % #items + 1])
		end
	end, command == "bnext" and "Next buffer" or "Previous buffer")
end
for key, delta in pairs({ bj = -1, bk = 1 }) do
	shared.map("n", "<leader>" .. key, function()
		shared.focus_editor()
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
	shared.map("n", "<leader>" .. key, function()
		shared.buffers()
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
local function delete_buffer(buf, force, replacement)
	local listed = vim.bo[buf].buflisted
	-- Wiping a displayed buffer closes its splits. Replace it in-place first.
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
			if not replacement then
				for _, candidate in ipairs(shared.buffers()) do
					if candidate ~= buf then
						replacement = candidate
						break
					end
				end
				replacement = replacement or vim.api.nvim_create_buf(true, false)
			end
			vim.api.nvim_win_call(win, function()
				vim.cmd.buffer({ replacement, bang = force })
			end)
		end
	end
	-- Leaving the last window can already wipe a buffer with bufhidden=wipe.
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = force })
	end
	local remaining = shared.buffers()
	if listed and #remaining == 1 then
		-- Merge duplicate editor panes only in this tab; preserve auxiliary windows.
		local keep = vim.api.nvim_get_current_buf() == remaining[1]
				and policy.is_editor(0)
				and vim.api.nvim_get_current_win()
			or nil
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_win_get_buf(win) == remaining[1] and policy.is_editor(win) then
				if not keep then
					keep = win
				elseif win ~= keep then
					vim.api.nvim_win_close(win, false)
				end
			end
		end
	end
end
shared.delete_buffer = delete_buffer -- filesystem actions use the same split-preserving policy
local function close_current_buffer(force)
	local is_terminal = vim.bo.buftype == "terminal"
	if vim.bo.modified and not is_terminal and not force then
		vim.notify("Unsaved changes: save the buffer before closing")
		return
	end
	delete_buffer(vim.api.nvim_get_current_buf(), force or is_terminal)
end
shared.map("n", "<leader>c", function()
	close_current_buffer(true)
end, "Force wipe current buffer (original binding)")
shared.map("n", "<leader>bw", function()
	close_current_buffer(false)
end, "Wipe buffer (protect unsaved files)")
shared.map("n", "<leader>bp", pick_buffer, "Pick buffer")
shared.map("n", "<leader>sb", pick_buffer, "Search buffers")
for i = 1, 9 do
	shared.map("n", "<A-" .. i .. ">", function()
		local items = shared.buffers()
		local b = items[i == 9 and #items or i]
		if b then
			shared.select_buffer(b)
		end
	end, "Go to buffer " .. i)
end
for key, side in pairs({ be = "all", bm = "all", bh = "left", bl = "right" }) do
	shared.map("n", "<leader>" .. key, function()
		shared.focus_editor()
		local current = vim.api.nvim_get_current_buf()
		local items = shared.buffers()
		local index = buffer_index(current, items)
		for position, b in ipairs(items) do
			if
				b ~= current
				and (side == "all" or (side == "left" and position < index) or (side == "right" and position > index))
			then
				local is_terminal = vim.bo[b].buftype == "terminal"
				if is_terminal or not vim.bo[b].modified then
					delete_buffer(b, is_terminal, current)
				end
			end
		end
	end, "Close " .. side .. " buffers (keep modified)")
end
