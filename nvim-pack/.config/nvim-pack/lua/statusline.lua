local policy = require("buffer_policy")
local Snacks = require("snacks")

-- -------------------------------------
-- Statusline: native renderer from nvim/init.lua
-- -------------------------------------
do
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
			fg, ctermfg =
				background_luminance > 0.179 and 0x000000 or 0xffffff, background_luminance > 0.179 and 0 or 15
		end
		vim.api.nvim_set_hl(0, "PackGitBranch", {
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
	local function set_pack_status_highlights()
		vim.api.nvim_set_hl(0, "PackLspMissing", { fg = "#ffffff", bg = "#af0000", bold = true })
		vim.api.nvim_set_hl(0, "PackLspMissingNC", { fg = "#ffffff", bg = "#af0000", bold = false, nocombine = true })
		git_mode_group = nil
		set_git_mode_highlight()
		for _, suffix in ipairs({ "", "NC" }) do
			local error_hl = vim.api.nvim_get_hl(0, { name = "StatusLine" .. suffix, link = false })
			error_hl.bold = suffix == ""
			if error_hl.cterm then
				error_hl.cterm.bold = suffix == ""
			end
			vim.api.nvim_set_hl(0, "StatusLine" .. suffix, error_hl)
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
			vim.api.nvim_set_hl(0, "PackStatusError" .. suffix, error_hl)
			local warn_hl = vim.deepcopy(error_hl)
			warn_hl.fg, warn_hl.ctermfg = "#ffd700", 220
			vim.api.nvim_set_hl(0, "PackStatusWarn" .. suffix, warn_hl)
		end
	end
	set_pack_status_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("pack-status-highlights", { clear = true }),
		callback = set_pack_status_highlights,
	})
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = "pack-status-highlights",
		callback = function()
			if set_git_mode_highlight() then
				vim.cmd("redrawstatus")
			end
		end,
	})
	vim.opt.laststatus = 2
	local language_status_visible = true
	function _G.PackGitStatus()
		local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
		local active = tonumber(vim.g.actual_curwin) or vim.api.nvim_get_current_win()
		if win ~= active then
			return ""
		end
		local branch = vim.b[vim.api.nvim_win_get_buf(win)].gitsigns_head
		local status = branch and branch ~= "" and ("[" .. branch .. "]") or ""
		if not status or status == "" then
			return ""
		end
		return "%#PackGitBranch# " .. status:gsub("%%", "%%%%") .. " %*"
	end
	local diagnostic_counts = {}
	vim.api.nvim_create_autocmd({ "DiagnosticChanged", "BufWipeout" }, {
		group = vim.api.nvim_create_augroup("pack-diagnostic-status", { clear = true }),
		callback = function(args)
			diagnostic_counts[args.buf] = nil
		end,
	})
	function _G.PackDiagnosticStatus()
		local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
		local active = tonumber(vim.g.actual_curwin) or vim.api.nvim_get_current_win()
		local error_group = win == active and "PackStatusError" or "PackStatusErrorNC"
		local warn_group = win == active and "PackStatusWarn" or "PackStatusWarnNC"
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
	local lsp_status_cache = {}
	function _G.PackLspStatus()
		if not language_status_visible then
			return ""
		end
		local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
		local buf = vim.api.nvim_win_get_buf(win)
		if not policy.is_source(buf) then
			return ""
		end
		local state = lsp_status_cache[buf]
		if not state then
			state = { clients = vim.lsp.get_clients({ bufnr = buf }) }
			lsp_status_cache[buf] = state
		end
		-- Preserve immediate stop detection without scanning every workspace client.
		for i = #state.clients, 1, -1 do
			if state.clients[i]:is_stopped() then
				table.remove(state.clients, i)
				state.text = nil
			end
		end
		if not state.text then
			local names = {}
			for _, client in ipairs(state.clients) do
				names[client.name:gsub("[%c]", " ")] = true
			end
			local sorted = vim.fn.sort(vim.tbl_keys(names))
			state.text = #sorted > 0 and ("[LSP: " .. table.concat(sorted, ", "):gsub("%%", "%%%%") .. "]") or ""
		end
		local active = tonumber(vim.g.actual_curwin) or vim.api.nvim_get_current_win()
		local missing_group = win == active and "PackLspMissing" or "PackLspMissingNC"
		return state.text ~= "" and state.text or ("%#" .. missing_group .. "#[LSP X]%*")
	end
	vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach", "BufWipeout" }, {
		group = vim.api.nvim_create_augroup("pack-lsp-status", { clear = true }),
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
	function _G.PackFormatStatus()
		if not language_status_visible then
			return ""
		end
		local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
		return require("format").status(vim.api.nvim_win_get_buf(win), win)
	end
	function _G.PackStatusline()
		local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
		if win ~= vim.api.nvim_get_current_win() then
			return " %f %= %y "
		end
		return "%{%v:lua.PackGitStatus()%} %<%{v:lua.PackFileContext()}%{%v:lua.PackBreadcrumbStatus()%} %m%r%h %= %{%v:lua.PackDiagnosticStatus()%} %{%v:lua.PackLspStatus()%} %{v:lua.PackFormatStatus()} %y | %4l:%3c | %3p%% "
	end
	function _G.PackFileContext()
		local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
		local buf = vim.api.nvim_win_get_buf(win)
		local file = vim.api.nvim_buf_get_name(buf)
		if not policy.is_editor(win) or file == "" then
			return file == "" and "[No Name]" or vim.fn.fnamemodify(file, ":~:.")
		end
		local project = require("project").for_dir(vim.fs.dirname(file))
		local prefix = project.root:gsub("/+$", "") .. "/"
		local path = project.recognized and file:sub(1, #prefix) == prefix and file:sub(#prefix + 1)
			or vim.fn.fnamemodify(file, ":~:.")
		return path
	end
	function _G.PackBreadcrumbStatus()
		local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
		return require("breadcrumbs").status(win)
	end
	vim.opt.statusline = "%!v:lua.PackStatusline()"
	Snacks.toggle({
		name = "LSP / formatter status",
		get = function()
			return language_status_visible
		end,
		set = function(state)
			language_status_visible = state
			vim.cmd("redrawstatus")
		end,
	}):map("<leader>Tl")
end
