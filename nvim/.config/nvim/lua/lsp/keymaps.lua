local policy = require("buffer_policy")
local shared = require("state")

-- Set file-buffer keymaps when a server attaches; the completion module manages autocompletion.
-- gd/gr/gD/K: direct navigation or lookup; gR/gi/gt: picker; <leader>la/lr/Tr: actions, rename and symbols.
return function(client, buf)
	if not policy.allows(buf) then
		vim.schedule(function()
			if vim.lsp.buf_is_attached(buf, client.id) then
				vim.lsp.buf_detach_client(buf, client.id)
			end
		end)
		return
	end
	-- gd handles provider selection; native tag operations must read the ctags file.
	vim.bo[buf].tagfunc = ""

	local actions = {
		gr = "references",
		gD = "declaration",
		K = "hover",
		["<leader>lr"] = "rename",
	}
	-- Direct jumps stay direct; the original Telescope mappings remain selectable lists.
	for key, method in pairs({ gR = "references", gi = "implementation", gt = "type_definition" }) do
		vim.keymap.set(
			"n",
			key,
			policy.guard(function()
				local opts = {
					on_list = function(list)
						if policy.allows(buf) then
							shared.location_picker(method, list.items)
						end
					end,
				}
				if method == "references" then
					vim.lsp.buf.references(nil, opts)
				else
					vim.lsp.buf[method](opts)
				end
			end),
			{ buf = buf, desc = "Select LSP " .. method }
		)
	end
	for key, action in pairs(actions) do
		vim.keymap.set("n", key, policy.guard(vim.lsp.buf[action]), { buf = buf, desc = "LSP: " .. action })
	end
	vim.keymap.set(
		{ "n", "x" },
		"<leader>la",
		policy.guard(vim.lsp.buf.code_action),
		{ buf = buf, desc = "Code action" }
	)
end
