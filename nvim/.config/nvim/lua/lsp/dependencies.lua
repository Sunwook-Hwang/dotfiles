local policy = require("buffer_policy")
local states = {}

local function refresh(client, state, buf)
	if
		state.seen[buf] == state.version
		or not client.attached_buffers[buf]
		or not policy.allows(buf)
		or not client:supports_method("textDocument/diagnostic", buf)
	then
		return
	end
	state.seen[buf] = state.version
	client:request("textDocument/diagnostic", {
		identifier = "ty",
		textDocument = { uri = vim.uri_from_bufnr(buf) },
	}, nil, buf)
end

local function refresh_visible(client, state)
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		refresh(client, state, vim.api.nvim_win_get_buf(win))
	end
end

local group = vim.api.nvim_create_augroup("flash-lsp-dependencies", { clear = true })
vim.api.nvim_create_autocmd("LspNotify", {
	group = group,
	callback = function(args)
		if args.data.method ~= "textDocument/didChange" then
			return
		end
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if not client or client.name ~= "ty" then
			return
		end
		-- ty updates its analysis but does not request diagnostics for dependent
		-- open documents after didChange. Native diagnostics cover the edited file.
		local state = states[client.id] or { version = 0, seen = {} }
		states[client.id] = state
		state.version = state.version + 1
		state.seen[args.buf] = state.version
		if state.scheduled then
			return
		end
		state.scheduled = true
		vim.schedule(function()
			state.scheduled = nil
			if states[client.id] ~= state or client:is_stopped() then
				return
			end
			-- Coalesce a burst of notifications; hidden documents catch up on entry.
			refresh_visible(client, state)
		end)
	end,
})
vim.api.nvim_create_autocmd("BufWinEnter", {
	group = group,
	callback = function(args)
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = args.buf, name = "ty" })) do
			local state = states[client.id]
			if state then
				refresh(client, state, args.buf)
			end
		end
	end,
})
vim.api.nvim_create_autocmd("TabEnter", {
	group = group,
	callback = function()
		for id, state in pairs(states) do
			local client = vim.lsp.get_client_by_id(id)
			if client and not client:is_stopped() then
				refresh_visible(client, state)
			end
		end
	end,
})
vim.api.nvim_create_autocmd("LspDetach", {
	group = group,
	callback = function(args)
		local id = args.data.client_id
		local client = vim.lsp.get_client_by_id(id)
		local state = states[id]
		if state then
			state.seen[args.buf] = nil
			for buf in pairs(client and client.attached_buffers or {}) do
				if buf ~= args.buf then
					return
				end
			end
			states[id] = nil
		end
	end,
})
