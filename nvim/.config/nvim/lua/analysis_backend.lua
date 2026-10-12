local M = {}
local providers, decisions = {}, {}

-- Register installed servers once. Attachment may still be initializing or restarting.
function M.register(filetypes, accepts)
	for _, ft in ipairs(filetypes) do
		providers[ft] = providers[ft] or {}
		table.insert(providers[ft], accepts)
		for buf, decision in pairs(decisions) do
			if decision.filetype == ft then
				decisions[buf] = nil
			end
		end
	end
end

-- The analysis backend belongs to the buffer's language, not to each RPC result.
function M.get(buf)
	buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
	local ft = vim.bo[buf].filetype
	local decision = decisions[buf]
	if decision and decision.filetype == ft then
		return decision.mode
	end
	local mode = "ctags"
	for _, accepts in ipairs(providers[ft] or {}) do
		if accepts(buf) then
			mode = "lsp"
			break
		end
	end
	if mode == "ctags" then
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
			local filetypes = client.config and client.config.filetypes
			if not filetypes or vim.list_contains(filetypes, ft) then
				mode = "lsp"
				break
			end
		end
	end
	decisions[buf] = { filetype = ft, mode = mode }
	return mode
end

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		-- Also recognize servers explicitly started outside this configuration.
		decisions[args.buf] = { filetype = vim.bo[args.buf].filetype, mode = "lsp" }
	end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
	callback = function(args)
		decisions[args.buf] = nil
	end,
})

return M
