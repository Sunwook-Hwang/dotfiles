local policy = require("buffer_policy")
-- -------------------------------------
-- Session management: persistence.nvim
-- -------------------------------------
require("persistence").setup({
	dir = (vim.env.XDG_STATE_HOME or vim.fn.expand("~/.local/state")) .. "/nvim/sessions/",
	branch = false,
})

-- Named auxiliary buffers must not become ordinary files on restore.
local excluded = {}
vim.api.nvim_create_autocmd("User", {
	pattern = "PersistenceSavePre",
	callback = function()
		excluded = {}
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if not policy.is_source(buf) then
				excluded[buf] = { listed = vim.bo[buf].buflisted, buftype = vim.bo[buf].buftype }
				vim.bo[buf].buflisted = false
				-- Oil's visible acwrite windows otherwise survive :mksession.
				if vim.bo[buf].buftype == "acwrite" then
					vim.bo[buf].buftype = "nofile"
				end
			end
		end
	end,
})
vim.api.nvim_create_autocmd("User", {
	pattern = "PersistenceSavePost",
	callback = function()
		for buf, options in pairs(excluded) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.bo[buf].buftype = options.buftype
				vim.bo[buf].buflisted = options.listed
			end
		end
		excluded = {}
	end,
})

vim.keymap.set("n", "<leader>pr", function()
	require("persistence").load()
end, { desc = "Restore session" })

vim.keymap.set("n", "<leader>pl", function()
	require("persistence").load({ last = true })
end, { desc = "Restore last session" })

vim.keymap.set("n", "<leader>pd", function()
	require("persistence").stop()
end, { desc = "Stop saving session" })

vim.keymap.set("n", "<leader>pS", function()
	require("persistence").select()
end, { desc = "Select session" })
