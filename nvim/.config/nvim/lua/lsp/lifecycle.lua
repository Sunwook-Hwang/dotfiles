local policy = require("buffer_policy")
local shared = require("state")
local M = {}

-- Complete buffer detachment before attaching a replacement. A late exit from
-- the old client must not tear down the replacement's semantic-token watchers.
function M.restart(client)
	if client:is_stopped() then
		return
	end
	local buffers = vim.tbl_keys(client.attached_buffers)
	local config = vim.deepcopy(client.config)
	for _, buf in ipairs(buffers) do
		vim.lsp.buf_detach_client(buf, client.id)
	end
	client:stop(true)
	local id = vim.lsp.start(config, { attach = false })
	if id then
		for _, buf in ipairs(buffers) do
			if policy.allows(buf) then
				vim.lsp.buf_attach_client(buf, id)
			end
		end
	end
	return id
end

-- Both explicit restarts and new-file recovery use the same detach/reattach path.
shared.map(
	"n",
	"<leader>ls",
	policy.guard(function()
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
			M.restart(client)
		end
	end),
	"Restart current buffer LSP clients"
)
vim.api.nvim_create_autocmd("User", {
	group = vim.api.nvim_create_augroup("nopack-lsp-lifecycle", { clear = true }),
	pattern = "NopackBufferRestricted",
	callback = function(args)
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = args.data.buf })) do
			vim.lsp.buf_detach_client(args.data.buf, client.id)
		end
	end,
})

-- :edit opens a buffer before a file exists. Only its first successful write
-- needs a directory refresh and recovery of ty's cached missing-module state.
do
	local writes, pending_files, pending_clients = {}, {}, {}
	local scheduled = false
	local group = vim.api.nvim_create_augroup("nopack-new-file", { clear = true })
	vim.api.nvim_create_autocmd("BufWritePre", {
		group = group,
		callback = function(args)
			writes[args.buf] = nil
			if not policy.is_source(args.buf) then
				return
			end
			local stat, _, code = vim.uv.fs_stat(args.match)
			if not stat and code == "ENOENT" then
				writes[args.buf] = {
					file = args.match,
					clients = vim.bo[args.buf].filetype == "python"
							and vim.lsp.get_clients({ bufnr = args.buf, name = "ty" })
						or {},
				}
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(args)
			writes[args.buf] = nil
		end,
	})
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(args)
			local write = writes[args.buf]
			writes[args.buf] = nil
			local file = write and write.file == args.match and vim.uv.fs_realpath(write.file)
			if not file then
				return
			end
			-- Explorer listings use resolved paths, including symlinked project roots.
			pending_files[file] = true
			for _, client in ipairs(write.clients) do
				pending_clients[client.id] = client
			end
			if scheduled then
				return
			end
			scheduled = true
			vim.schedule(function()
				local files, clients = pending_files, pending_clients
				pending_files, pending_clients, scheduled = {}, {}, false
				-- Batch :wall into one restart per affected ty instance. Reattach
				-- its loaded buffers without reloading files or changing their text.
				for _, client in pairs(clients) do
					M.restart(client)
				end
				vim.api.nvim_exec_autocmds("User", {
					pattern = "NopackFilesCreated",
					data = { files = files },
					modeline = false,
				})
			end)
		end,
	})
end

return M
