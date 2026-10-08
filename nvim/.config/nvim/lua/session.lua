local policy = require("buffer_policy")
local shared = require("state")

-- Share file sessions with Pack; auxiliary windows and mode-specific options stay local.
local session_dir = (vim.env.XDG_STATE_HOME or vim.fn.expand("~/.local/state")) .. "/nvim/sessions/"
vim.fn.mkdir(session_dir, "p")
local save_session = true
local function is_tree(buf)
	local name = vim.api.nvim_buf_get_name(buf)
	return vim.bo[buf].filetype == "netrw"
		or vim.bo[buf].filetype == "flash-explorer"
		or name:match("^flash://") ~= nil
		or (name ~= "" and vim.fn.isdirectory(name) == 1)
end
local function session_path()
	return session_dir .. vim.fn.getcwd():gsub("[\\/:]+", "%%") .. ".vim"
end
local function sessions()
	local paths, modified = {}, {}
	for _, path in ipairs(vim.fn.glob(session_dir .. "*.vim", false, true)) do
		local stat = vim.uv.fs_stat(path)
		if stat and stat.type == "file" then
			paths[#paths + 1], modified[path] = path, stat.mtime.sec
		end
	end
	table.sort(paths, function(a, b)
		return modified[a] > modified[b]
	end)
	return paths
end
-- One filter for automatic saves, :mksession and Neovim 0.13's :restart.
local excluded
local function exclude_auxiliary_buffers()
	if excluded then
		return
	end
	excluded = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if not policy.is_source(buf) or is_tree(buf) then
			excluded[buf] = { listed = vim.bo[buf].buflisted, buftype = vim.bo[buf].buftype }
			vim.bo[buf].buflisted = false
			-- Unlisting alone does not exclude a visible acwrite tree window.
			if vim.bo[buf].buftype == "acwrite" or vim.bo[buf].buftype == "" then
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
local function write_session()
	if not save_session then
		return
	end
	local has_file = false
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if policy.is_source(buf) and not is_tree(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
			has_file = true
			break
		end
	end
	if not has_file then
		return
	end
	shared.restore_window_zooms()
	exclude_auxiliary_buffers()
	local ok, err = pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(session_path()))
	restore_auxiliary_buffers()
	if not ok then
		vim.notify(err, vim.log.levels.ERROR)
	end
end
if vim.fn.has("nvim-0.13") == 1 then
	vim.api.nvim_create_autocmd("SessionWritePre", {
		callback = function()
			shared.restore_window_zooms()
			exclude_auxiliary_buffers()
		end,
	})
	vim.api.nvim_create_autocmd("SessionWritePost", { callback = restore_auxiliary_buffers })
end
local function restore_session(path)
	if path and vim.fn.filereadable(path) == 1 then
		shared.restore_window_zooms()
		-- Native sessions use :only; run them in an editor, never a utility float.
		shared.focus_editor()
		local loading, previous = vim.g.SessionLoad, vim.v.this_session
		local options =
			{ scrolloff = vim.go.scrolloff, sidescrolloff = vim.go.sidescrolloff, shortmess = vim.o.shortmess }
		local ok, err = pcall(vim.cmd, "source " .. vim.fn.fnameescape(path))
		-- Older sessions can contain directory windows; discard those panes and buffers.
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if is_tree(buf) and not vim.bo[buf].modified then
				vim.api.nvim_buf_delete(buf, { force = false })
			end
		end
		if not ok then
			-- An interrupted session does not reach its generated cleanup commands.
			vim.g.SessionLoad, vim.v.this_session = loading, previous
			for name, value in pairs(options) do
				vim.go[name] = value
			end
			vim.notify("Session restore failed: " .. tostring(err), vim.log.levels.ERROR)
		end
	else
		vim.notify("No saved session")
	end
end
function shared.select_session()
	vim.ui.select(sessions(), {
		prompt = "Sessions:",
		format_item = function(path)
			local directory = path:sub(#session_dir + 1, -5):gsub("%%", "/")
			if vim.fn.has("win32") == 1 then
				directory = directory:gsub("^(%w)/", "%1:/")
			end
			return vim.fn.fnamemodify(directory, ":p:~")
		end,
	}, restore_session)
end
shared.map("n", "<leader>pr", function()
	restore_session(session_path())
end, "Restore directory session")
function shared.restore_last_session()
	restore_session(sessions()[1])
end
shared.map("n", "<leader>pl", shared.restore_last_session, "Restore last session")
shared.map("n", "<leader>pd", function()
	save_session = false
end, "Stop saving session")
shared.map("n", "<leader>pS", shared.select_session, "Select session")
vim.api.nvim_create_autocmd("VimLeavePre", { callback = write_session })
