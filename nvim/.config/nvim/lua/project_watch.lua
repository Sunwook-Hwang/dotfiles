-- Live refresh for changes made outside Neovim (agents, Git, other editors).
-- Buffer text is reloaded by file_watch / native autoread. This module covers what
-- is derived from the project tree: explorer entries, Git marks, status and signs.
local api = vim.api
local shared = require("state")
local policy = require("buffer_policy")
local explorer = require("explorer")

-- inotify cannot watch a tree with one handle; Linux watches each directory.
local recursive = vim.fn.has("linux") == 0
local max_directories = 4096 -- stay well inside fs.inotify.max_user_watches
local watches = {} -- root -> { handles = { [directory] = handle }, count = n }
local created, flush_pending, sync_pending = {}, false, false

local ignored_patterns = vim.tbl_map(function(name)
	return "^" .. vim.pesc(name):gsub("%%%*", ".*") .. "$"
end, shared.ignored_dirs)
local function ignored(name)
	for _, pattern in ipairs(ignored_patterns) do
		if name:match(pattern) then
			return true
		end
	end
	return false
end

local function flush()
	flush_pending = false
	local files = created
	created = {}
	api.nvim_exec_autocmds("User", { pattern = "NopackExternalChange", modeline = false, data = { files = files } })
end

local watch_directory
-- `relative` is the changed path below `root`; nil means "something changed".
local function changed(watch, root, relative, events)
	if relative then
		local git = relative:match("^%.git/(.*)$")
		if git then
			-- Git's own locks and object writes are not state changes yet.
			if git:match("%.lock$") or git:match("^objects/") then
				return
			end
		else
			for name in relative:gmatch("[^/]+") do
				if ignored(name) then
					return
				end
			end
			if events.rename then
				local path = root .. "/" .. relative
				created[path] = true -- created, removed or renamed: its parent listing is stale
				if not recursive then
					local handle = watch.handles[path]
					local stat = vim.uv.fs_stat(path)
					if handle and not stat then
						handle:close()
						watch.handles[path], watch.count = nil, watch.count - 1
					elseif stat and stat.type == "directory" then
						watch_directory(watch, root, path)
					end
				end
			end
		end
	end
	if not flush_pending then
		flush_pending = true
		vim.defer_fn(flush, 150)
	end
end

local function start(watch, root, directory, flags)
	local handle = vim.uv.new_fs_event()
	if not handle then
		return
	end
	local prefix = directory == root and "" or directory:sub(#root + 2) .. "/"
	local started = handle:start(directory, flags, function(err, filename, events)
		if not err then
			changed(watch, root, filename and prefix .. filename, events)
		end
	end)
	if not started then
		handle:close()
		return
	end
	watch.handles[directory], watch.count = handle, watch.count + 1
	return true
end

-- Linux: watch `directory` and everything below it, breadth-first up to the limit.
function watch_directory(watch, root, directory)
	local queue = { directory }
	for _, current in ipairs(queue) do
		if watch.count >= max_directories then
			return
		end
		if not watch.handles[current] and start(watch, root, current, {}) then
			for name, kind in vim.fs.dir(current) do
				if kind == "directory" and not ignored(name) then
					queue[#queue + 1] = current .. "/" .. name
				end
			end
		end
	end
end

local function watch_root(root, tree)
	local watch = { handles = {}, count = 0 }
	watches[root] = watch
	if not tree then
		start(watch, root, root, {}) -- outside Git: this directory only
	elseif recursive then
		start(watch, root, root, { recursive = true })
	else
		watch_directory(watch, root, root)
		local stat = vim.uv.fs_stat(root .. "/.git")
		if stat and stat.type == "directory" then
			start(watch, root, root .. "/.git", {}) -- index and HEAD: commit, stage, checkout
		end
	end
end

-- Watch the projects that are on screen; drop the ones that no longer are.
local function sync()
	sync_pending = false
	local wanted = {}
	for _, win in ipairs(api.nvim_list_wins()) do
		local buf = api.nvim_win_get_buf(win)
		if explorer.is_buffer(buf) then
			local top = explorer.root(buf)
			if top ~= "" then
				local root = shared.find_git_root(top)
				wanted[root or top] = root ~= nil
			end
		elseif policy.is_source(buf) and api.nvim_buf_get_name(buf) ~= "" then
			local root = shared.find_git_root(vim.fs.dirname(api.nvim_buf_get_name(buf)))
			if root then
				wanted[root] = true
			end
		end
	end
	for root, watch in pairs(watches) do
		if wanted[root] == nil then
			for _, handle in pairs(watch.handles) do
				handle:close()
			end
			watches[root] = nil
		end
	end
	for root, tree in pairs(wanted) do
		if not watches[root] then
			watch_root(root, tree)
		end
	end
end

api.nvim_create_autocmd({ "BufWinEnter", "WinClosed", "FileType" }, {
	group = api.nvim_create_augroup("nopack-project-watch", { clear = true }),
	callback = function()
		if not sync_pending then
			sync_pending = true
			vim.schedule(sync)
		end
	end,
})
