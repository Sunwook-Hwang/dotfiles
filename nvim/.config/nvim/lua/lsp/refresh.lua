local policy = require("buffer_policy")
local M = {}
local clients = {}
local methods = {
	["textDocument/diagnostic"] = "diagnostic",
	["textDocument/semanticTokens/full"] = "tokens",
	["textDocument/semanticTokens/full/delta"] = "tokens",
	["textDocument/semanticTokens/range"] = "range",
	["textDocument/completion"] = "completion",
	["textDocument/prepareRename"] = "prepare-rename",
	["textDocument/rename"] = "rename",
}

local function stop_retry(state)
	if state and state.retrying then
		state.retrying[state.original_id] = nil
	end
	if state and state.timer and not state.timer:is_closing() then
		state.timer:stop()
		state.timer:close()
	end
end

-- Native handlers own rendering and edits; only current document responses reach them.
-- Retry background diagnostics/tokens when the server invalidates its snapshot.
function M.attach(client)
	local request = client.request
	local cancel = client.cancel_request
	local retrying = {}
	function client:cancel_request(id)
		local state = retrying[id]
		if state then
			state.cancelled = true
			stop_retry(state)
			id = state.id
		end
		return cancel(self, id)
	end
	function client:request(method, params, handler, buf)
		local kind = methods[method]
		if not kind then
			return request(self, method, params, handler, buf)
		end
		buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
		local buffers = clients[self.id] or {}
		clients[self.id] = buffers
		local requests = buffers[buf] or {}
		buffers[buf] = requests
		local key = kind .. ":" .. (params.identifier or "")
		local previous = requests[key]
		if previous and previous.retrying then
			self:cancel_request(previous.original_id)
		end
		stop_retry(previous)
		local version = vim.lsp.util.buf_versions[buf]
		local state = { version = version, delay = previous and previous.version == version and previous.delay }
		requests[key] = state
		handler = handler or self.handlers[method] or vim.lsp.handlers[method]
		local function current(ctx)
			return buffers[buf] == requests
				and requests[key] == state
				and not state.cancelled
				and not self:is_stopped()
				and self.attached_buffers[buf]
				and policy.allows(buf)
				and params.textDocument.uri == vim.uri_from_bufnr(buf)
				and ctx.version == vim.lsp.util.buf_versions[buf]
		end
		local function response(err, result, ctx)
			-- Late errors must not clear a newer semantic request's native state.
			if not current(ctx) then
				stop_retry(state)
				return
			end
			-- Native highlighting also requests full tokens alongside its range preview.
			-- Recover only the full request; its native range preview has its own lifecycle.
			local retry = (kind == "diagnostic" or kind == "tokens")
				and err
				and (
					err.code == vim.lsp.protocol.ErrorCodes.ContentModified
					or (
						err.code == vim.lsp.protocol.ErrorCodes.ServerCancelled
						and (type(err.data) ~= "table" or err.data.retriggerRequest ~= false)
					)
				)
			if not retry then
				stop_retry(state)
				requests[key] = nil
				-- Complete the original callback with its logical request ID. The
				-- native token engine owns that ID and retains its delta/cache state.
				ctx.request_id = state.original_id or ctx.request_id
				return handler(err, result, ctx)
			end
			state.original_id = state.original_id or ctx.request_id
			state.retrying = retrying
			retrying[state.original_id] = state
			-- Retry only explicit transient failures, with bounded frequency. Success,
			-- a newer request or detachment ends recovery; there is no idle polling.
			state.delay = math.min((state.delay or 25) * 2, 1000)
			state.timer = vim.defer_fn(function()
				state.timer = nil
				if
					current(ctx)
					and (kind ~= "tokens" or vim.lsp.semantic_tokens.is_enabled({ bufnr = buf, client_id = self.id }))
				then
					local ok, id = request(self, method, params, response, buf)
					state.id = id
					if not ok then
						stop_retry(state)
						requests[key] = nil
						handler(nil, nil, ctx)
					end
				else
					stop_retry(state)
				end
			end, state.delay)
		end
		local ok, id = request(self, method, params, response, buf)
		state.id = id
		return ok, id
	end
end

local group = vim.api.nvim_create_augroup("flash-lsp-refresh", { clear = true })
vim.api.nvim_create_autocmd("LspRequest", {
	group = group,
	callback = function(args)
		local data = args.data
		if data.request.type ~= "cancel" then
			return
		end
		local buffers = clients[data.client_id]
		for key, state in pairs(buffers and buffers[args.buf] or {}) do
			if state.id == data.request_id then
				stop_retry(state)
				buffers[args.buf][key] = nil
			end
		end
	end,
})
vim.api.nvim_create_autocmd("LspDetach", {
	group = group,
	callback = function(args)
		local id = args.data.client_id
		local buffers = clients[id]
		if buffers then
			for _, state in pairs(buffers[args.buf] or {}) do
				stop_retry(state)
			end
			buffers[args.buf] = nil
			if not next(buffers) then
				clients[id] = nil
			end
		end
	end,
})

return M
