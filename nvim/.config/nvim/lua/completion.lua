local policy = require("buffer_policy")
-- =========================================
-- ======== COMPLETION / SNIPPETS ========
-- =========================================
-- Native Blink replacement: built-in LSP completion and snippets. This module also manages automatic LSP popups.
-- Ctrl-Space: request; Ctrl-n/p: select; Enter: confirm; Tab/Shift-Tab: navigate snippets or candidates.
vim.keymap.set("i", "<C-Space>", function()
	if not policy.allows(0) then
		return
	end
	if #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/completion" }) > 0 then
		vim.lsp.completion.get()
	else
		vim.api.nvim_feedkeys(vim.keycode("<C-n>"), "n", false)
	end
end, { desc = "Complete from LSP or buffer" })
vim.keymap.set("i", "<CR>", function()
	return vim.fn.pumvisible() == 1 and vim.fn.complete_info().selected >= 0 and "<C-y>" or "<CR>"
end, { expr = true, desc = "Accept selected completion / newline" })
for key, direction in pairs({ ["<Tab>"] = 1, ["<S-Tab>"] = -1 }) do
	vim.keymap.set({ "i", "s" }, key, function()
		if vim.snippet.active({ direction = direction }) then
			vim.snippet.jump(direction)
		elseif vim.fn.pumvisible() == 1 then
			vim.api.nvim_feedkeys(vim.keycode(direction == 1 and "<C-n>" or "<C-p>"), "n", false)
		else
			vim.api.nvim_feedkeys(vim.keycode(key), "n", false)
		end
	end, { desc = "Snippet tabstop / completion / " .. key })
end
-- Buffers without completion providers use words/tags; connected providers use the async engine.
local completion_buffers, pending_completion = {}, {}
local function buffer_completion(buf)
	local eligible = policy.allows(buf)
	vim.bo[buf].autocomplete = eligible
		and #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/completion" }) == 0
	completion_buffers[buf] = eligible
end
vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		if not policy.allows(args.buf) then
			return
		end
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if client:supports_method("textDocument/completion") then
			local completion = client.server_capabilities.completionProvider
			completion.triggerCharacters = completion.triggerCharacters or {}
			-- Also open completion while typing identifiers, not just after server punctuation.
			local triggers = {}
			for _, char in ipairs(completion.triggerCharacters) do
				triggers[char] = true
			end
			for char in ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"):gmatch(".") do
				if not triggers[char] then
					table.insert(completion.triggerCharacters, char)
				end
			end
			vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
			vim.bo[args.buf].autocomplete = false
			completion_buffers[args.buf] = true
		end
	end,
})
vim.api.nvim_create_autocmd("User", {
	pattern = "NopackBufferRestricted",
	callback = function(args)
		buffer_completion(args.data.buf)
	end,
})
vim.api.nvim_create_autocmd({ "BufEnter", "FileType", "LspDetach" }, {
	callback = function(args)
		if
			pending_completion[args.buf]
			or (args.event == "BufEnter" and completion_buffers[args.buf] == policy.allows(args.buf))
		then
			return
		end
		pending_completion[args.buf] = true
		vim.schedule(function()
			pending_completion[args.buf] = nil
			if vim.api.nvim_buf_is_loaded(args.buf) then
				buffer_completion(args.buf)
			end
		end)
	end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
	callback = function(args)
		completion_buffers[args.buf], pending_completion[args.buf] = nil, nil
	end,
})
