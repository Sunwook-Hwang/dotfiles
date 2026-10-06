local policy = require("buffer_policy")

-- =========================================
-- ========== LARGE FILE GUARDS ==========
-- =========================================
-- Disable expensive features above 2 MiB, 50,000 lines or 10,000 bytes in a single line.
-- Only merge inspection ranges in on_lines; inspect buffers and disable features outside textlock.
local watched_buffers, protected_options = {}, {}
local function protect_large_file(buf)
	if not vim.api.nvim_buf_is_loaded(buf) then
		return
	end
	local saved = protected_options[buf]
	if not saved then
		saved = {
			syntax = vim.bo[buf].syntax,
			indentexpr = vim.bo[buf].indentexpr,
			autocomplete = vim.bo[buf].autocomplete,
			windows = {},
		}
		protected_options[buf] = saved
	end
	policy.restrict(buf)
	if vim.bo[buf].syntax ~= "OFF" then
		vim.bo[buf].syntax = "OFF"
	end
	vim.bo[buf].indentexpr = ""
	vim.bo[buf].autocomplete = false
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		if not saved.windows[win] then
			saved.windows[win] = {
				foldmethod = vim.wo[win].foldmethod,
				cursorcolumn = vim.wo[win].cursorcolumn,
				cursorline = vim.wo[win].cursorline,
			}
		end
		-- Like :setlocal: limit the guard to this buffer, preserving window defaults.
		vim.wo[win][0].foldmethod = "manual"
		vim.wo[win][0].cursorcolumn = false
		vim.wo[win][0].cursorline = false
	end
end
vim.api.nvim_create_autocmd("User", {
	pattern = "NopackBufferRestricted",
	callback = function(args)
		local buf = args.data.buf
		if not vim.api.nvim_buf_is_loaded(buf) then
			return
		end
		pcall(vim.treesitter.stop, buf)
	end,
})
local function check_large_file(buf, first, last)
	if vim.b[buf].nopack_large_file or not vim.api.nvim_buf_is_loaded(buf) then
		return
	end
	local count = vim.api.nvim_buf_line_count(buf)
	local large = count > 50000 or vim.api.nvim_buf_get_offset(buf, count) > 2 * 1024 * 1024
	if not large then
		first, last = math.max(0, math.min(first, count)), math.max(0, math.min(last, count))
		-- Fetch bounded batches, not a byte-offset lookup for every line.
		for start = first, last - 1, 512 do
			for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, start, math.min(start + 512, last), false)) do
				if #line > 10000 then
					large = true
					break
				end
			end
			if large then
				break
			end
		end
	end
	if large then
		protect_large_file(buf)
	end
end
local function queue_large_file_check(buf, first, last, added)
	local state = watched_buffers[buf]
	if not state or vim.b[buf].nopack_large_file then
		return
	end
	state.first = math.min(state.first or first, first)
	-- Positive shifts conservatively extend the pending range; deletions are
	-- clamped at execution time. No changed line is lost during a paste burst.
	state.last = math.max(state.last and (state.last + math.max(0, added or 0)) or last, last)
	if state.pending then
		return
	end
	state.pending = true
	vim.schedule(function()
		if watched_buffers[buf] ~= state then
			return
		end
		state.pending = false
		local start, finish = state.first, state.last
		state.first, state.last = nil, nil
		if vim.api.nvim_buf_is_loaded(buf) then
			check_large_file(buf, start, finish)
		end
	end)
end
vim.api.nvim_create_autocmd("BufReadPre", {
	callback = function(args)
		-- A fresh read starts a new protection decision for this buffer.
		local saved = protected_options[args.buf]
		if saved then
			for _, name in ipairs({ "syntax", "indentexpr", "autocomplete" }) do
				vim.bo[args.buf][name] = saved[name]
			end
			for win, options in pairs(saved.windows) do
				if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == args.buf then
					for name, value in pairs(options) do
						vim.wo[win][0][name] = value
					end
				end
			end
			protected_options[args.buf] = nil
		end
		vim.b[args.buf].nopack_large_file = nil
		local stat = vim.uv.fs_stat(vim.api.nvim_buf_get_name(args.buf))
		if stat and stat.size > 2 * 1024 * 1024 then
			policy.restrict(args.buf)
		end
	end,
})
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "FileType", "BufWinEnter" }, {
	callback = function(args)
		local buf = args.buf
		if not policy.is_source(buf) then
			return
		end
		if vim.b[buf].nopack_large_file then
			protect_large_file(buf)
			return
		end
		if not watched_buffers[buf] then
			watched_buffers[buf] = {}
			local attached = vim.api.nvim_buf_attach(buf, false, {
				on_lines = function(_, changed_buf, _, first, old_last, new_last)
					queue_large_file_check(changed_buf, first, new_last, new_last - old_last)
				end,
				on_reload = function(_, reloaded_buf)
					queue_large_file_check(reloaded_buf, 0, math.huge)
				end,
				on_detach = function(_, detached_buf)
					watched_buffers[detached_buf] = nil
				end,
			})
			if attached then
				check_large_file(buf, 0, math.huge)
			else
				watched_buffers[buf] = nil
			end
		end
	end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
	callback = function(args)
		protected_options[args.buf] = nil
	end,
})
