local policy = require("buffer_policy")
local pending = {}

-- 0.13 refreshes hidden buffers natively; only 0.12 needs this catch-up.
local refresh = vim.lsp.diagnostic._refresh
if refresh then
	-- Native 0.12 pull diagnostics skip didChange for buffers without a window.
	-- Remember only those skipped updates, then catch up once the buffer is shown.
	local group = vim.api.nvim_create_augroup("flash-lsp-diagnostics", { clear = true })
	vim.api.nvim_create_autocmd("LspNotify", {
		group = group,
		callback = function(args)
			if args.data.method ~= "textDocument/didChange" or not policy.allows(args.buf) then
				return
			end
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if
				client
				and client:supports_method("textDocument/diagnostic", args.buf)
				and #vim.fn.win_findbuf(args.buf) == 0
			then
				pending[args.buf] = pending[args.buf] or {}
				pending[args.buf][client.id] = true
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = group,
		callback = function(args)
			local clients = pending[args.buf]
			pending[args.buf] = nil
			if not clients or not policy.allows(args.buf) then
				return
			end
			for id in pairs(clients) do
				local client = vim.lsp.get_client_by_id(id)
				if client and not client:is_stopped() and client.attached_buffers[args.buf] then
					refresh(args.buf, id)
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout", "LspDetach" }, {
		group = group,
		callback = function(args)
			if args.event ~= "LspDetach" then
				pending[args.buf] = nil
			elseif pending[args.buf] then
				pending[args.buf][args.data.client_id] = nil
			end
		end,
	})
end

local handlers = {
	["textDocument/diagnostic"] = function(err, result, ctx)
		-- Cancellation is advisory: responses may outlive edits or their connection.
		-- Reject them before the native handler changes diagnostics or retries a request.
		local client = vim.lsp.get_client_by_id(ctx.client_id)
		if
			not client
			or client:is_stopped()
			or not client.attached_buffers[ctx.bufnr]
			or not policy.allows(ctx.bufnr)
			or (ctx.version ~= nil and ctx.version ~= vim.lsp.util.buf_versions[ctx.bufnr])
		then
			return
		end
		vim.lsp.diagnostic.on_diagnostic(err, result, ctx)
		if result and pending[ctx.bufnr] then
			pending[ctx.bufnr][ctx.client_id] = nil
		end
	end,
}

return handlers
