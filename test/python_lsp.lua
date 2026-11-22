local root, case = vim.env.FLASH_TEST_ROOT, vim.env.FLASH_TEST_CASE
local main, mainwin = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
local function wait(label, predicate)
	assert(vim.wait(5000, predicate, 20), label)
end
local client
wait("Python LSP did not attach", function()
	client = vim.lsp.get_clients({ bufnr = main, name = vim.env.FLASH_TEST_SERVER })[1]
	return client
		and client.initialized
		and (client.name ~= "ty" or client:supports_method("textDocument/diagnostic", main))
end)
local id = client.id
local recovered_diagnostics = false
vim.api.nvim_create_autocmd("LspRequest", {
	callback = function(args)
		if
			args.buf == main
			and args.data.client_id ~= id
			and args.data.request.method == "textDocument/diagnostic"
			and args.data.request.type == "complete"
		then
			recovered_diagnostics = true
		end
	end,
})
local function errors(buf)
	return vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR })
end
local function edit(buf, lines)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end
local function provider()
	vim.cmd.vsplit(root .. "/provider.py")
	local buf = vim.api.nvim_get_current_buf()
	wait("Provider did not attach to the same LSP", function()
		return client.attached_buffers[buf]
	end)
	return buf
end
local function same_client()
	local attached = vim.lsp.get_clients({ bufnr = main, name = vim.env.FLASH_TEST_SERVER })
	assert(#attached == 1 and attached[1].id == id and not client:is_stopped(), "LSP restarted or detached")
end
if case == "cross_file" then
	local buf = provider()
	for iteration = 1, 3 do
		edit(buf, { "def current() -> str:", '    return "wrong"' })
		wait("Unsaved provider edit did not update consumer diagnostics", function()
			return #errors(main) > 0
		end)
		edit(buf, { "def current() -> int:", "    return " .. iteration })
		wait("Consumer error remained after unsaved correction", function()
			return #errors(main) == 0
		end)
	end
	same_client()
elseif case == "tab_switch" or case == "hidden_buffer" then
	local buf = provider()
	edit(main, { 'value: int = "wrong"' })
	wait("Initial consumer diagnostics did not complete", function()
		return #errors(main) > 0
	end)
	edit(main, { "from provider import current", "value: int = current()" })
	wait("Consumer diagnostics did not settle before hiding", function()
		return #errors(main) == 0
	end)
	local tab = vim.api.nvim_get_current_tabpage()
	if case == "tab_switch" then
		vim.cmd("tab split")
	else
		vim.api.nvim_win_close(mainwin, false)
	end
	edit(buf, { "def current() -> str:", '    return "wrong"' })
	-- A real server round trip establishes that didChange was processed, without
	-- pulling consumer diagnostics and inadvertently making the test pass.
	assert(client:request_sync("textDocument/documentSymbol", {
		textDocument = { uri = vim.uri_from_bufnr(buf) },
	}, 5000, buf))
	local drained = false
	vim.schedule(function()
		vim.schedule(function()
			drained = true
		end)
	end)
	wait("Queued change handlers did not finish", function()
		return drained
	end)
	if case == "tab_switch" then
		vim.api.nvim_set_current_tabpage(tab)
	else
		vim.cmd("sbuffer " .. main)
	end
	wait("Consumer diagnostics stayed stale after showing the buffer", function()
		return #errors(main) > 0
	end)
	same_client()
elseif case == "definition" then
	local buf = provider()
	-- Establish a missing name before adding it in the unsaved provider.
	vim.api.nvim_set_current_win(mainwin)
	edit(main, { "import provider", "value = provider.updated()" })
	wait("Missing function was not diagnosed", function()
		return #errors(main) > 0
	end)
	edit(buf, { "def updated() -> int:", "    return 1" })
	vim.api.nvim_win_set_cursor(mainwin, { 2, 19 })
	vim.fn.maparg("gd", "n", false, true).callback()
	wait("gd missed the unsent provider change", function()
		return vim.api.nvim_get_current_buf() == buf
	end)
	assert(vim.api.nvim_win_get_cursor(0)[1] == 1, "gd jumped to the wrong definition")
	same_client()
elseif case == "new_module" then
	wait("Missing module was not diagnosed", function()
		return #errors(main) > 0
	end)
	local buf = provider()
	edit(buf, { "def current() -> int:", "    return 1" })
	vim.cmd("silent write")
	wait("Saving new module did not update the importer", function()
		local active = vim.lsp.get_clients({ bufnr = main, name = client.name })
		return #active == 1
			and active[1].initialized
			and (active[1].id == id or recovered_diagnostics)
			and #errors(main) == 0
	end)
	if client.name == "ty" then
		-- Preserve FLASH's existing first-save recovery while ty still caches
		-- missing modules after receiving the real file-creation notification.
		local active = vim.lsp.get_clients({ bufnr = main, name = client.name })
		assert(#active == 1 and active[1].initialized, "New-file recovery left LSP disconnected")
		client = active[1]
	else
		same_client()
	end
elseif case == "delayed_response" then
	-- Pyright can register pull diagnostics after initialization/configuration.
	-- Wait for real diagnostics before deciding which transport to delay.
	edit(main, { 'value: int = "initial"' })
	wait("Initial error was not diagnosed", function()
		return #errors(main) > 0
	end)
	edit(main, { "value: int = 0" })
	wait("Initial correction did not complete", function()
		return #errors(main) == 0
	end)
	local held, done, corrected = false, false, false
	local function delay(callback, err, result, ctx)
		local items = result and (result.items or result.diagnostics)
		held = held or (items and #items > 0)
		vim.defer_fn(function()
			callback(err, result, ctx)
			if corrected and items and #items == 0 then
				done = true
			end
		end, 250)
	end
	if client:supports_method("textDocument/diagnostic", main) then
		local request = client.rpc.request
		client.rpc.request = function(method, params, callback, ...)
			if method == "textDocument/diagnostic" then
				local original = callback
				callback = function(err, result, request_id)
					delay(original, err, result, request_id)
				end
			end
			return request(method, params, callback, ...)
		end
	else
		local callback = client.handlers["textDocument/publishDiagnostics"]
		client.handlers["textDocument/publishDiagnostics"] = function(...)
			delay(callback, ...)
		end
	end
	edit(main, { 'value: int = "wrong"' })
	wait("No delayed error response was captured", function()
		return held
	end)
	edit(main, { "value: int = 1" })
	corrected = true
	wait("Current diagnostics did not complete", function()
		return done
	end)
	assert(#errors(main) == 0, "Late error response restored an obsolete diagnostic")
	same_client()
else
	error("Unknown regression case: " .. tostring(case))
end
client:stop(true)
print("FLASH_LSP_TEST_PASS:" .. case)
vim.cmd("qa!")
