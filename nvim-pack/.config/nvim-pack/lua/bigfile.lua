-- Snacks handles files on open; retain protection for growth and isolated long lines.
local policy = require("buffer_policy")
local protect_large_file
do
	local watched_buffers, protected_options = {}, {}
	local features = { "indent", "scroll", "words", "scope", "dim" }
	local function protect_options(buf)
		if not protected_options[buf] then
			local saved = {
				syntax = vim.bo[buf].syntax,
				indentexpr = vim.bo[buf].indentexpr,
				autocomplete = vim.bo[buf].autocomplete,
				features = {},
				windows = {},
			}
			for _, feature in ipairs(features) do
				saved.features[feature] = vim.b[buf]["snacks_" .. feature]
			end
			protected_options[buf] = saved
		end
		-- Filetype scripts can re-enable these while opening a buffer.
		vim.bo[buf].syntax = "OFF"
		vim.bo[buf].indentexpr = ""
		vim.bo[buf].autocomplete = false
		for _, win in ipairs(vim.fn.win_findbuf(buf)) do
			local windows = protected_options[buf].windows
			if not windows[win] then
				windows[win] = {}
				for _, name in ipairs({ "foldmethod", "cursorcolumn", "cursorline", "wrap" }) do
					windows[win][name] = vim.wo[win][name]
				end
			end
			-- Change only this buffer's window options, not defaults inherited by new buffers.
			for name, value in pairs({ foldmethod = "manual", cursorcolumn = false, cursorline = false, wrap = false }) do
				vim.api.nvim_set_option_value(name, value, { win = win, scope = "local" })
			end
		end
	end
	protect_large_file = function(buf)
		if not vim.api.nvim_buf_is_loaded(buf) then
			return
		end
		protect_options(buf)
		policy.restrict(buf)
		pcall(vim.treesitter.stop, buf)
	end
	vim.api.nvim_create_autocmd("BufReadPre", {
		callback = function(args)
			local saved = protected_options[args.buf]
			if saved then
				for _, name in ipairs({ "syntax", "indentexpr", "autocomplete" }) do
					vim.bo[args.buf][name] = saved[name]
				end
				for _, feature in ipairs(features) do
					vim.b[args.buf]["snacks_" .. feature] = saved.features[feature]
				end
				for win, options in pairs(saved.windows) do
					if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == args.buf then
						for name, value in pairs(options) do
							vim.api.nvim_set_option_value(name, value, { win = win, scope = "local" })
						end
					end
				end
				protected_options[args.buf] = nil
			end
			vim.b[args.buf].large_file = nil
			if vim.bo[args.buf].filetype == "bigfile" then
				vim.bo[args.buf].filetype = ""
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		callback = function(args)
			protected_options[args.buf] = nil
		end,
	})
	local function check_large_file(buf, first, last)
		if vim.b[buf].large_file or not vim.api.nvim_buf_is_loaded(buf) then
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
		if not state or vim.b[buf].large_file then
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
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "FileType", "BufWinEnter" }, {
		callback = function(args)
			local buf = args.buf
			if not policy.is_source(buf) then
				return
			end
			if vim.b[buf].large_file then
				protect_options(buf)
				return
			end
			-- The native bigfile FileType callback runs after this supplemental listener.
			if vim.bo[buf].filetype == "bigfile" then
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
					-- Check once before FileType plugins attach; edits are batched below.
					check_large_file(buf, 0, math.huge)
				else
					watched_buffers[buf] = nil
				end
			end
		end,
	})
end

return {
	enabled = true,
	size = 2 * 1024 * 1024,
	line_length = 10000, -- Snacks checks the average; the supplement checks individual lines.
	setup = function(ctx)
		protect_large_file(ctx.buf)
	end,
}
