local policy = require("buffer_policy")
local M = {}
local states = {}
local method = "textDocument/documentSymbol"

function M.client(buf)
	local clients = vim.lsp.get_clients({ bufnr = buf, method = method })
	table.sort(clients, function(a, b)
		return a.id < b.id
	end)
	return clients[1]
end

local function deliver(listener, err, result, state)
	vim.schedule(function()
		if listener.active then
			listener.active = false
			listener.callback(err, result, state.context)
		end
	end)
end

local function finish(state, err, result)
	state.completed = true
	state.request = nil
	state.result = result
	if err and states[state.context.buf] == state then
		states[state.context.buf] = nil
	end
	for listener in pairs(state.listeners) do
		deliver(listener, err, result, state)
	end
	state.listeners = {}
end

function M.clear(buf)
	local state = states[buf]
	states[buf] = nil
	if state and not state.completed then
		state.cancelled = true
		if state.request then
			state.client:cancel_request(state.request)
		end
		finish(state, { code = vim.lsp.protocol.ErrorCodes.RequestCancelled, message = "Symbol request cancelled" })
	end
end

-- Outline and statusline share requests and successful results for the same source version.
-- Closing one consumer only cancels the RPC when no other consumer is waiting.
function M.request(buf, client, callback, force)
	local state = states[buf]
	if
		state
		and (state.client ~= client or not policy.source_unchanged(state.context) or (force and state.completed))
	then
		M.clear(buf)
		state = nil
	end
	if not state then
		state = { client = client, context = policy.source_context(buf), listeners = {} }
		states[buf] = state
	elseif force and not state.completed then
		-- Explicit refresh restarts the shared RPC, retaining the other consumers.
		if state.request then
			client:cancel_request(state.request)
		end
		state.attempt, state.request, state.started, state.retried = nil, nil, nil, nil
	end
	local listener = { active = true, callback = callback }
	if state.completed then
		deliver(listener, nil, state.result, state)
	else
		state.listeners[listener] = true
	end
	local function send()
		if state.cancelled then
			return
		end
		if not policy.allows(buf) or not policy.source_unchanged(state.context) then
			finish(state, { code = vim.lsp.protocol.ErrorCodes.ContentModified, message = "Source buffer changed" })
			return
		end
		local answered = false
		local attempt = {}
		state.attempt = attempt
		local ok, id = client:request(
			method,
			{ textDocument = { uri = vim.uri_from_bufnr(buf) } },
			function(err, result)
				answered = true
				if state.cancelled or state.attempt ~= attempt then
					return
				end
				state.request = nil
				if
					err
					and err.code == vim.lsp.protocol.ErrorCodes.ContentModified
					and not state.retried
					and policy.allows(buf)
					and policy.source_unchanged(state.context)
				then
					-- A server-side project change can invalidate an otherwise unchanged document.
					state.retried = true
					vim.schedule(function()
						if state.attempt == attempt then
							send()
						end
					end)
					return
				end
				finish(state, err, result)
			end,
			buf
		)
		if not ok then
			finish(
				state,
				{ code = vim.lsp.protocol.ErrorCodes.InternalError, message = "Symbol request could not be sent" }
			)
		elseif not answered then
			state.request = id
		end
	end
	if not state.started then
		state.started = true
		send()
	end
	return function()
		listener.active = false
		state.listeners[listener] = nil
		if states[buf] == state and not state.completed and not next(state.listeners) then
			M.clear(buf)
		end
	end
end

vim.api.nvim_create_autocmd({ "BufUnload", "BufFilePost", "FileType" }, {
	callback = function(args)
		M.clear(args.buf)
	end,
})
vim.api.nvim_create_autocmd("LspDetach", {
	callback = function(args)
		local state = states[args.buf]
		if state and state.client.id == args.data.client_id then
			M.clear(args.buf)
		end
	end,
})
vim.api.nvim_create_autocmd("User", {
	pattern = "NopackBufferRestricted",
	callback = function(args)
		M.clear(args.data.buf)
	end,
})

return M
