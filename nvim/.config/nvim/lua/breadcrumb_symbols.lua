local policy = require("buffer_policy")
local M = {}
local states = {}
local queued = {}
local enabled

function M.clear(buf)
	local state = states[buf]
	states[buf] = nil
	queued[buf] = nil
	if state and state.request then
		state.client:cancel_request(state.request)
	end
end

local function before(a, b)
	return a.line < b.line or (a.line == b.line and a.character < b.character)
end
local function contains(range, position)
	return not before(position, range.start) and before(position, range["end"])
end
local function index_ranges(nodes)
	local furthest
	for _, node in ipairs(nodes) do
		if not furthest or before(furthest, node.range["end"]) then
			furthest = node.range["end"]
		end
		node.prefix_end = furthest
		if node.children then
			index_ranges(node.children)
		end
	end
end
local function normalize(symbols, buf)
	local result = {}
	for _, symbol in ipairs(symbols) do
		local location = symbol.location
		if not location or vim.uri_to_fname(location.uri) == vim.api.nvim_buf_get_name(buf) then
			result[#result + 1] = {
				name = symbol.name,
				kind = symbol.kind,
				range = symbol.range or location.range,
				selection = symbol.selectionRange or (location and location.range) or symbol.range,
				children = symbol.children and normalize(symbol.children, buf),
			}
		end
	end
	table.sort(result, function(a, b)
		if before(a.range.start, b.range.start) then
			return true
		end
		if before(b.range.start, a.range.start) then
			return false
		end
		return before(b.range["end"], a.range["end"])
	end)
	if symbols[1] and symbols[1].location then
		local roots, stack = {}, {}
		for _, symbol in ipairs(result) do
			while #stack > 0 do
				local range = stack[#stack].range
				if
					contains(range, symbol.range.start)
					and not before(range["end"], symbol.range["end"])
					and (before(range.start, symbol.range.start) or before(symbol.range["end"], range["end"]))
				then
					break
				end
				table.remove(stack)
			end
			local parent = stack[#stack]
			if parent then
				parent.children = parent.children or {}
				parent.children[#parent.children + 1] = symbol
			else
				roots[#roots + 1] = symbol
			end
			stack[#stack + 1] = symbol
		end
		return roots
	end
	return result
end

local function refresh(buf, force)
	if not enabled() or not policy.allows(buf) or not vim.iter(vim.fn.win_findbuf(buf)):any(policy.is_editor) then
		M.clear(buf)
		return
	end
	local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentSymbol" })
	table.sort(clients, function(a, b)
		return a.id < b.id
	end)
	local client = clients[1]
	if not client then
		M.clear(buf)
		states[buf] = { symbols = {} }
		return
	end
	local previous = states[buf]
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	if not force and previous and previous.client == client and previous.tick == tick then
		return
	end
	M.clear(buf)
	local state = {
		client = client,
		symbols = previous and previous.client == client and previous.tick == tick and previous.symbols or {},
		tick = tick,
	}
	states[buf] = state
	local completed = false
	local ok, id = client:request(
		"textDocument/documentSymbol",
		{ textDocument = { uri = vim.uri_from_bufnr(buf) } },
		function(err, symbols)
			completed = true
			state.request = nil
			vim.schedule(function()
				if states[buf] ~= state then
					return
				end
				if not enabled() or not policy.allows(buf) then
					M.clear(buf)
					return
				end
				if
					err
					or symbols == nil
					or symbols == vim.NIL
					or state.tick ~= vim.api.nvim_buf_get_changedtick(buf)
				then
					return
				end
				state.symbols = normalize(symbols, buf)
				index_ranges(state.symbols)
				vim.cmd("redrawstatus")
			end)
		end,
		buf
	)
	state.request = ok and not completed and id or nil
end

function M.get_symbols(buf, win, cursor)
	if not enabled() or not policy.allows(buf) or not policy.is_editor(win) then
		return {}
	end
	local state = states[buf]
	if not state or not state.client or state.tick ~= vim.api.nvim_buf_get_changedtick(buf) then
		return {}
	end
	local encoding = state.client.offset_encoding or "utf-16"
	local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
	local position = { line = cursor[1] - 1, character = vim.str_utfindex(line, encoding, cursor[2], false) }
	local result = {}
	local function visit(nodes)
		-- Skip symbols starting after the cursor; prefix ends also bound overlaps.
		local low, high = 1, #nodes
		while low <= high do
			local middle = math.floor((low + high) / 2)
			if before(position, nodes[middle].range.start) then
				high = middle - 1
			else
				low = middle + 1
			end
		end
		for index = high, 1, -1 do
			local node = nodes[index]
			if not before(position, node.prefix_end) then
				break
			end
			if contains(node.range, position) then
				result[#result + 1] = node
				if node.children then
					visit(node.children)
				end
				return
			end
		end
	end
	visit(state.symbols)
	return result
end

M.refresh = refresh

function M.setup(is_enabled)
	enabled = is_enabled
	local group = vim.api.nvim_create_augroup("NopackBreadcrumbSymbols", { clear = true })
	vim.api.nvim_create_autocmd({
		"BufEnter",
		"BufWinEnter",
		"BufFilePost",
		"FileType",
		"TextChanged",
		"InsertLeave",
		"BufWritePost",
		"FileChangedShellPost",
		"LspAttach",
		"LspDetach",
	}, {
		group = group,
		callback = function(args)
			-- Invalidate identities before accepting replies; attachment changes finish after the event.
			if args.event == "BufFilePost" or args.event == "FileType" then
				M.clear(args.buf)
			end
			if states[args.buf] or (enabled() and policy.allows(args.buf)) then
				local force = args.event == "BufWritePost" or args.event == "FileChangedShellPost"
				if queued[args.buf] then
					queued[args.buf].force = queued[args.buf].force or force
					return
				end
				local pending = { force = force }
				queued[args.buf] = pending
				vim.schedule(function()
					if queued[args.buf] == pending then
						queued[args.buf] = nil
						refresh(args.buf, pending.force)
					end
				end)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufUnload", {
		group = group,
		callback = function(args)
			M.clear(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "NopackBufferRestricted",
		callback = function(args)
			M.clear(args.data.buf)
		end,
	})
	return M
end

return M
