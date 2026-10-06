local policy = require("buffer_policy")
local shared = require("state")

local git_mode_group
local function set_git_mode_highlight()
	local mode = vim.fn.mode():sub(1, 1)
	local group = "Identifier"
	if mode == "i" then
		group = "String"
	elseif mode == "v" or mode == "V" or mode == "\22" then
		group = "Constant"
	end
	if git_mode_group == group then
		return false
	end
	git_mode_group = group
	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local accent = vim.api.nvim_get_hl(0, { name = group, link = false })
	local bg = (accent.reverse and accent.bg or accent.fg) or normal.fg or 0x808080
	local ctermbg = accent.cterm and accent.cterm.reverse and accent.ctermbg or accent.ctermfg
	local function luminance(color)
		local result = 0
		for i, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
			local channel = math.floor(color / 256 ^ (3 - i)) % 256 / 255
			result = result + weight * (channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4)
		end
		return result
	end
	local background_luminance = luminance(bg)
	local function contrast(color)
		local value = luminance(color)
		return (math.max(value, background_luminance) + 0.05) / (math.min(value, background_luminance) + 0.05)
	end
	local fg, ctermfg = normal.bg or 0x000000, normal.ctermbg or 0
	if contrast(normal.fg or 0xffffff) > contrast(fg) then
		fg, ctermfg = normal.fg or 0xffffff, normal.ctermfg or 15
	end
	if contrast(fg) < 4.5 then
		fg, ctermfg = background_luminance > 0.179 and 0x000000 or 0xffffff, background_luminance > 0.179 and 0 or 15
	end
	vim.api.nvim_set_hl(0, "NopackGitBranch", {
		fg = fg,
		bg = bg,
		ctermfg = ctermfg,
		ctermbg = ctermbg or normal.ctermfg or 8,
		bold = true,
		reverse = false,
		nocombine = true,
	})
	return true
end
local function set_nopack_status_highlights()
	local inactive = vim.api.nvim_get_hl(0, { name = "StatusLineNC", link = false })
	inactive.bold = false
	if inactive.cterm then
		inactive.cterm.bold = false
	end
	vim.api.nvim_set_hl(0, "StatusLineNC", inactive)
	vim.api.nvim_set_hl(0, "NopackLspMissing", { fg = "#ffffff", bg = "#af0000", bold = true })
	vim.api.nvim_set_hl(0, "NopackLspMissingNC", { fg = "#ffffff", bg = "#af0000", bold = false, nocombine = true })
	git_mode_group = nil
	set_git_mode_highlight()
	for _, suffix in ipairs({ "", "NC" }) do
		local error_hl = vim.api.nvim_get_hl(0, { name = "StatusLine" .. suffix, link = false })
		if error_hl.reverse then
			error_hl.bg = error_hl.fg
		end
		if error_hl.cterm and error_hl.cterm.reverse then
			error_hl.ctermbg = error_hl.ctermfg
			error_hl.cterm.reverse = false
		end
		if error_hl.cterm then
			error_hl.cterm.nocombine = true
		end
		error_hl.nocombine = true
		error_hl.reverse, error_hl.fg, error_hl.ctermfg = false, "#ff0000", 9
		vim.api.nvim_set_hl(0, "NopackStatusError" .. suffix, error_hl)
		local warn_hl = vim.deepcopy(error_hl)
		warn_hl.fg, warn_hl.ctermfg = "#ffd700", 220
		vim.api.nvim_set_hl(0, "NopackStatusWarn" .. suffix, warn_hl)
	end
	shared.picker_selection_highlight()
end
set_nopack_status_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("nopack-status-highlights", { clear = true }),
	callback = set_nopack_status_highlights,
})
vim.api.nvim_create_autocmd("ModeChanged", {
	group = "nopack-status-highlights",
	callback = function()
		if set_git_mode_highlight() then
			vim.cmd("redrawstatus")
		end
	end,
})
vim.opt.laststatus = 2
shared.language_status_visible = true
local diagnostic_counts, lsp_status_cache = {}, {}
vim.api.nvim_create_autocmd({ "DiagnosticChanged", "BufWipeout" }, {
	group = vim.api.nvim_create_augroup("nopack-diagnostic-status", { clear = true }),
	callback = function(args)
		diagnostic_counts[args.buf] = nil
	end,
})
function shared.status_clients(buf)
	local state = lsp_status_cache[buf]
	if not state then
		state = { clients = vim.lsp.get_clients({ bufnr = buf }) }
		lsp_status_cache[buf] = state
	end
	-- Keep stop detection immediate without scanning every workspace client.
	for i = #state.clients, 1, -1 do
		if state.clients[i]:is_stopped() then
			table.remove(state.clients, i)
			state.text = nil
		end
	end
	return state
end
function _G.NopackGitStatus()
	local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
	local active = tonumber(vim.g.actual_curwin) or vim.api.nvim_get_current_win()
	if win ~= active then
		return ""
	end
	local status = vim.b[vim.api.nvim_win_get_buf(win)].nopack_git_status
	if not status or status == "" then
		return ""
	end
	return "%#NopackGitBranch# " .. status:gsub("%%", "%%%%") .. " %*"
end
function _G.NopackDiagnosticStatus()
	local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
	local active = tonumber(vim.g.actual_curwin) or vim.api.nvim_get_current_win()
	local error_group = win == active and "NopackStatusError" or "NopackStatusErrorNC"
	local warn_group = win == active and "NopackStatusWarn" or "NopackStatusWarnNC"
	local buf = vim.api.nvim_win_get_buf(win)
	local counts = diagnostic_counts[buf]
	if not counts then
		counts = vim.diagnostic.count(buf)
		diagnostic_counts[buf] = counts
	end
	local parts = {}
	for _, item in ipairs({ { "ERROR", "E:" }, { "WARN", "W:" }, { "HINT", "H:" } }) do
		local count = counts[vim.diagnostic.severity[item[1]]] or 0
		if count > 0 then
			local text = item[2] .. " " .. count
			local group = item[1] == "ERROR" and error_group or item[1] == "WARN" and warn_group
			parts[#parts + 1] = group and ("%#" .. group .. "#" .. text .. "%*") or text
		end
	end
	return table.concat(parts, " ")
end
function _G.NopackLspStatus()
	if not shared.language_status_visible then
		return ""
	end
	local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	if not policy.is_source(buf) then
		return ""
	end
	local state = shared.status_clients(buf)
	if not state.text then
		local names = {}
		for _, client in ipairs(state.clients) do
			names[client.name:gsub("[%c]", " ")] = true
		end
		local sorted = vim.fn.sort(vim.tbl_keys(names))
		state.text = #sorted > 0 and ("[LSP: " .. table.concat(sorted, ", "):gsub("%%", "%%%%") .. "]") or ""
	end
	if state.text == "" and shared.ctags_kind and policy.allows(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
		return "[CTAGS: " .. shared.ctags_kind .. "]"
	end
	local active = tonumber(vim.g.actual_curwin) or vim.api.nvim_get_current_win()
	local missing_group = win == active and "NopackLspMissing" or "NopackLspMissingNC"
	return state.text ~= "" and state.text or ("%#" .. missing_group .. "#[LSP X]%*")
end
vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach", "BufWipeout" }, {
	group = vim.api.nvim_create_augroup("nopack-lsp-status", { clear = true }),
	callback = function(args)
		lsp_status_cache[args.buf] = nil
		if args.event == "BufWipeout" then
			return
		end
		-- LspDetach fires before the client is removed from the buffer.
		vim.schedule(function()
			lsp_status_cache[args.buf] = nil
			vim.cmd("redrawstatus")
		end)
	end,
})
function _G.NopackStatusline()
	local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
	if win ~= vim.api.nvim_get_current_win() then
		return " %f %= %y "
	end
	return "%{%v:lua.NopackGitStatus()%} %<%{v:lua.NopackFileContext()}%{%v:lua.NopackBreadcrumbStatus()%} %m%r%h %= %{%v:lua.NopackDiagnosticStatus()%} %{%v:lua.NopackLspStatus()%} %{v:lua.NopackFormatStatus()} %y | %4l:%3c | %3p%% "
end
vim.opt.statusline = "%!v:lua.NopackStatusline()"
-- Render indent guides natively; do not recreate extmarks on every text change or cursor movement.
-- Draw guides only in leading spaces at shiftwidth intervals; do not extend them across empty lines.

function _G.NopackFileContext()
	local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
	local file = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
	if not policy.is_editor(win) or file == "" then
		return file == "" and "[No Name]" or vim.fn.fnamemodify(file, ":~:.")
	end
	local root, _, recognized = shared.find_project(vim.fs.dirname(file))
	local prefix = root:gsub("/+$", "") .. "/"
	return recognized and file:sub(1, #prefix) == prefix and file:sub(#prefix + 1) or vim.fn.fnamemodify(file, ":~:.")
end
function _G.NopackBreadcrumbStatus()
	local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
	return require("breadcrumbs").status(win)
end
