local policy = require("buffer_policy")
-- -------------------------------------
-- Session management: persistence.nvim
-- -------------------------------------
local persistence = require("persistence")
persistence.setup({
	dir = (vim.env.XDG_STATE_HOME or vim.fn.expand("~/.local/state")) .. "/nvim/sessions/",
	branch = false,
})

-- Filter auxiliary buffers only while writing, including explicit saves and failures.
local excluded
local function exclude_auxiliary_buffers()
	if excluded then
		return
	end
	require("terminal").restore_zoom()
	require("window").restore_all()
	excluded = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if not policy.is_source(buf) then
			excluded[buf] = { listed = vim.bo[buf].buflisted, buftype = vim.bo[buf].buftype }
			vim.bo[buf].buflisted = false
			if vim.bo[buf].buftype == "acwrite" then
				vim.bo[buf].buftype = "nofile"
			end
		end
	end
end
local function restore_auxiliary_buffers()
	for buf, options in pairs(excluded or {}) do
		if vim.api.nvim_buf_is_valid(buf) then
			vim.bo[buf].buftype = options.buftype
			vim.bo[buf].buflisted = options.listed
		end
	end
	excluded = nil
end
local save = persistence.save
persistence.save = function()
	exclude_auxiliary_buffers()
	local ok, err = pcall(save)
	restore_auxiliary_buffers()
	if not ok then
		error(err, 0)
	end
end

if vim.fn.exists("##SessionWritePre") == 1 then
	local group = vim.api.nvim_create_augroup("pack-session-write", { clear = true })
	vim.api.nvim_create_autocmd("SessionWritePre", { group = group, callback = exclude_auxiliary_buffers })
	vim.api.nvim_create_autocmd("SessionWritePost", { group = group, callback = restore_auxiliary_buffers })
end

local load = persistence.load
persistence.load = function(opts)
	require("terminal").restore_zoom()
	require("window").restore_all()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if policy.is_editor(win) then
			vim.api.nvim_set_current_win(win)
			break
		end
	end
	return load(opts)
end

-- Stat each session once; files may disappear between globbing and inspection.
persistence.list = function()
	local sessions = {}
	local dir = require("persistence.config").options.dir
	for _, path in ipairs(vim.fn.glob(dir .. "*.vim", true, true)) do
		local stat = vim.uv.fs_stat(path)
		if stat and stat.type == "file" then
			sessions[#sessions + 1] = { path = path, modified = stat.mtime.sec }
		end
	end
	table.sort(sessions, function(a, b)
		return a.modified > b.modified
	end)
	return vim.tbl_map(function(session)
		return session.path
	end, sessions)
end

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
