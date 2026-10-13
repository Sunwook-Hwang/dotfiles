local policy = require("buffer_policy")
local M = {}
local clients = {}
local methods = {
	["textDocument/diagnostic"] = "diagnostic",
	["textDocument/semanticTokens/full"] = "tokens",
	["textDocument/semanticTokens/full/delta"] = "tokens",
	["textDocument/semanticTokens/range"] = "range",
}

local function stop_retry(state)
	if state and state.timer and not state.timer:is_closing() then
		state.timer:stop()
		state.timer:close()
	end
end

-- Native renderers own diagnostics and tokens. This layer only keeps their
-- latest background request alive when the server invalidates its snapshot.
function M.attach(client)
	local request = client.request
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
		stop_retry(previous)
		local version = vim.lsp.util.buf_versions[buf]
		local state = { version = version, delay = previous and previous.version == version and previous.delay }
		requests[key] = state
		handler = handler or self.handlers[method] or vim.lsp.handlers[method]
		local function current(ctx)
			return buffers[buf] == requests
				and requests[key] == state
				and not self:is_stopped()
				and self.attached_buffers[buf]
				and policy.allows(buf)
				and params.textDocument.uri == vim.uri_from_bufnr(buf)
				and ctx.version == vim.lsp.util.buf_versions[buf]
		end
		local ok, id = request(self, method, params, function(err, result, ctx)
			-- Late errors must not clear a newer semantic request's native state.
			if not current(ctx) then
				return
			end
			-- Native highlighting also requests full tokens alongside its range preview.
			-- Let that request recover; a range retry would cancel it and reset every client.
			local retry = kind ~= "range"
				and err
				and (
					err.code == vim.lsp.protocol.ErrorCodes.ContentModified
					or (
						err.code == vim.lsp.protocol.ErrorCodes.ServerCancelled
						and (type(err.data) ~= "table" or err.data.retriggerRequest ~= false)
					)
				)
			if not retry then
				requests[key] = nil
				return handler(err, result, ctx)
			end
			if kind ~= "diagnostic" then
				-- Release the completed native token request before asking for a new one.
				handler(nil, nil, ctx)
			end
			-- Retry only explicit transient failures, with bounded frequency. Success,
			-- a newer request or detachment ends recovery; there is no idle polling.
			state.delay = math.min((state.delay or 25) * 2, 1000)
			state.timer = vim.defer_fn(function()
				state.timer = nil
				if current(ctx) then
					if kind == "diagnostic" then
						self:request(method, params, handler, buf)
					else
						vim.lsp.semantic_tokens.force_refresh(buf)
					end
				end
			end, state.delay)
		end, buf)
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
