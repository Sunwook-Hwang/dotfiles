-- Native editable directory buffers: row IDs retain file identity through yy/p.
local shared = require("state")
function shared.sidebar_width()
	return math.max(20, math.min(40, math.floor(vim.o.columns * 0.25)))
end
-- winfixwidth belongs to the window itself, so release it when its sidebar leaves.
function shared.fix_sidebar_width(win)
	local saved = vim.w[win].nopack_sidebar_width or { value = vim.wo[win].winfixwidth }
	saved.buf = vim.api.nvim_win_get_buf(win)
	vim.w[win].nopack_sidebar_width = saved
	vim.wo[win][0].winfixwidth = true
end
vim.api.nvim_create_autocmd("BufWinEnter", {
	group = vim.api.nvim_create_augroup("nopack-sidebar-width", { clear = true }),
	callback = function(args)
		local saved = vim.w.nopack_sidebar_width
		if saved and saved.buf ~= args.buf then
			vim.opt_local.winfixwidth = saved.value
			vim.w.nopack_sidebar_width = nil
		end
	end,
})

local M = {}
vim.g.loaded_netrwPlugin = 1 -- directory buffers are owned by this explorer
vim.g.loaded_nvim_dir_plugin = 1 -- Neovim 0.13: keep the built-in directory browser disabled too
local states, entries, ids, next_id = {}, {}, {}, 0
local copied_ids = {} -- retain identities that may still be in named/numbered registers
local group = vim.api.nvim_create_augroup("flash-directory", { clear = true })
local saving, locks
local tree_ns = vim.api.nvim_create_namespace("flash-directory-tree")
local function close_help(buf)
	local state = states[buf]
	local help = state and state.help
	if not help then
		return
	end
	state.help = nil
	if vim.api.nvim_win_is_valid(help.win) and vim.api.nvim_win_get_buf(help.win) == help.buf then
		local focused = vim.api.nvim_get_current_win() == help.win
		vim.api.nvim_win_close(help.win, true)
		if focused and vim.api.nvim_win_is_valid(help.owner) then
			vim.api.nvim_set_current_win(help.owner)
		end
	end
end

local window_options = {}
local ui_options = { "conceallevel", "concealcursor", "wrap", "winbar", "foldenable", "spell", "cursorcolumn", "list" }
local function restore_window(win, saved)
	for name, value in pairs(saved or {}) do
		vim.wo[win][0][name] = value
	end
end
local function focus_editor()
	local origin = vim.api.nvim_get_current_win()
	local previous = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		previous[win] = true
	end
	shared.focus_editor()
	local win = vim.api.nvim_get_current_win()
	if not previous[win] then
		restore_window(win, window_options[origin])
	end
end
local function encode(name)
	return (
		name:gsub("%%", "%%25")
			:gsub("^ +", function(spaces)
				return spaces:gsub(" ", "%%20")
			end)
			:gsub("\n", "%%0A")
			:gsub("\r", "%%0D")
			:gsub("\t", "%%09")
	)
end
local function decode(name)
	return (name:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end
local function stat_key(stat)
	return stat and table.concat({ stat.type, stat.dev, stat.ino, stat.size, stat.mtime.sec, stat.mtime.nsec }, ":")
end
local function buffer_path(buf, parents)
	if states[buf] then
		return states[buf].root
	end
	local name = vim.api.nvim_buf_get_name(buf)
	if name ~= "" and vim.bo[buf].buftype == "" then
		-- Resolve directory aliases (/tmp, symlinked projects), preserving file symlinks.
		local directory = vim.fs.dirname(name)
		local parent = parents[directory]
		if parent == nil then
			local ancestor, suffix = directory, ""
			while true do
				local resolved = vim.uv.fs_realpath(ancestor)
				if resolved then
					parent = resolved .. suffix
					break
				end
				local above = vim.fs.dirname(ancestor)
				if above == ancestor then
					parent = false
					break
				end
				suffix = "/" .. vim.fs.basename(ancestor) .. suffix
				ancestor = above
			end
			parents[directory] = parent
		end
		if parent then
			return vim.fs.joinpath(parent, vim.fs.basename(name))
		end
	end
	return name
end
local function checked(value, err)
	if not value then
		error(err or "Filesystem operation failed", 0)
	end
	return value
end
-- Filesystem work runs in libuv's worker pool; never spin a nested vim.wait loop.
local function fs(method, ...)
	local thread = coroutine.running()
	local arguments = { ... }
	arguments[#arguments + 1] = vim.schedule_wrap(function(err, result)
		local ok, failure = coroutine.resume(thread, result, err)
		if not ok then
			vim.notify(failure, vim.log.levels.ERROR)
		end
	end)
	checked(vim.uv[method](unpack(arguments)))
	return coroutine.yield()
end
local function remove(path)
	local stat = checked(fs("fs_lstat", path))
	if stat.type == "directory" then
		checked(fs("fs_chmod", path, bit.bor(stat.mode % 4096, 448)))
		local scan = checked(fs("fs_scandir", path))
		while true do
			local name = vim.uv.fs_scandir_next(scan)
			if not name then
				break
			end
			remove(vim.fs.joinpath(path, name))
		end
		checked(fs("fs_rmdir", path))
	else
		checked(fs("fs_unlink", path))
	end
end
local function copy(source, target, defer_mode)
	local stat = checked(fs("fs_lstat", source))
	if stat.type == "directory" then
		local mode = stat.mode % 4096
		checked(fs("fs_mkdir", target, bit.bor(mode, 448))) -- writable while populating
		local scan = checked(fs("fs_scandir", source))
		while true do
			local name = vim.uv.fs_scandir_next(scan)
			if not name then
				break
			end
			copy(vim.fs.joinpath(source, name), vim.fs.joinpath(target, name))
		end
		if not defer_mode then
			checked(fs("fs_chmod", target, mode))
		end
		return mode
	elseif stat.type == "link" then
		checked(fs("fs_symlink", checked(fs("fs_readlink", source)), target))
	elseif stat.type == "file" then
		checked(fs("fs_copyfile", source, target, 1)) -- exclusive; never overwrite
	else
		error("Cannot copy special file: " .. source, 0)
	end
end

function M.is_buffer(buf)
	return vim.bo[buf].filetype == "flash-explorer"
end
function M.root(buf)
	return states[buf] and states[buf].root or ""
end
-- Parse each edited tree once per changedtick; cursor and Git drawing reuse it.
local function tree_rows(buf)
	local state = states[buf]
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	if state.tick == tick then
		return state.rows, state.row_error
	end
	local rows, parents, failure = {}, { [0] = state.root }
	for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		if line ~= "" then
			local id, label = line:match("^/(%d+) (.*)$")
			label = label or line
			local spaces, name = label:match("^( *)(.*)$")
			local depth = #spaces / 2
			local directory = name:sub(-1) == "/"
			name = decode(directory and name:sub(1, -2) or name)
			if #spaces % 2 ~= 0 or not parents[depth] then
				failure = "Invalid tree indentation at row " .. index .. "; collapse folders before deleting their row"
				break
			end
			local invalid = name == "" or name:sub(1, 1) == "/" or name:find("[\\%z]") or name:find("//", 1, true)
			for component in name:gmatch("[^/]+") do
				invalid = invalid or component == "." or component == ".."
			end
			if invalid then
				failure = "Use a relative path without '.' or '..': " .. label
				break
			end
			local target = vim.fs.joinpath(parents[depth], name)
			rows[index] = { id = tonumber(id), target = target, directory = directory, depth = depth }
			for level in pairs(parents) do
				if level > depth then
					parents[level] = nil
				end
			end
			if directory then
				parents[depth + 1] = target
			end
		end
	end
	state.tick, state.rows, state.row_error = tick, rows, failure
	return rows, failure
end
function M.path(buf, line, index)
	if not states[buf] then
		return
	end
	if not index then
		for row, text in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
			if text == line then
				index = row
				break
			end
		end
	end
	local row = tree_rows(buf)[index]
	return row and row.target
end
-- Decorations follow the affected text rows, never cursor motion or filesystem scans.
local function draw_tree(buf, first, last)
	-- Edits can move old marks to the end-of-buffer position, past the last row.
	local finish = last == vim.api.nvim_buf_line_count(buf) and -1 or last
	vim.api.nvim_buf_clear_namespace(buf, tree_ns, first, finish)
	for offset, line in ipairs(vim.api.nvim_buf_get_lines(buf, first, last, false)) do
		local label = line:match("^/%d+ (.*)$")
		label = label or line
		local spaces = label:match("^ *") or ""
		local depth = math.floor(#spaces / 2)
		local index = first + offset - 1
		if depth > 0 then
			vim.api.nvim_buf_set_extmark(buf, tree_ns, index, #(line:match("^/%d+ ") or ""), {
				virt_text = { { string.rep("│ ", depth), "NonText" } },
				virt_text_pos = "overlay",
				right_gravity = false,
			})
		end
	end
end
local render
render = function(buf)
	local state, lines, originals, unchecked = states[buf], {}, {}, {}
	if state.filtering then
		return
	end
	local function visit(directory, depth)
		local listing = state.children[directory]
		if not listing then
			listing = {}
			local scan = checked(vim.uv.fs_scandir(directory))
			while true do
				local name = vim.uv.fs_scandir_next(scan)
				if not name then
					break
				end
				if state.hidden or name:sub(1, 1) ~= "." then
					local path = vim.fs.joinpath(directory, name)
					local stat = checked(vim.uv.fs_lstat(path))
					listing[#listing + 1] = {
						name = name,
						path = path,
						key = stat_key(stat),
						size = stat.size,
						mtime = stat.mtime.sec,
						directory = stat.type == "directory" or stat.type == "link" and vim.fn.isdirectory(path) == 1,
						expandable = stat.type == "directory" or stat.type == "link" and vim.fn.isdirectory(path) == 1,
					}
				end
			end
			table.sort(listing, function(a, b)
				if a.directory ~= b.directory then
					return a.directory
				end
				local av, bv = a[state.sort], b[state.sort]
				if av == bv then
					av, bv = a.name, b.name
				end
				return state.reverse and av > bv or not state.reverse and av < bv
			end)
			state.children[directory] = listing
		end
		for _, entry in ipairs(listing) do
			if
				(state.hidden or entry.name:sub(1, 1) ~= ".") and (state.show_ignored or not state.ignored[entry.path])
			then
				if not state.show_ignored and state.ignored[entry.path] == nil then
					unchecked[#unchecked + 1] = entry.path
				end
				local id = ids[entry.path]
				if not id then
					next_id = next_id + 1
					id, ids[entry.path] = next_id, next_id
				end
				entry.id = id
				entries[id], originals[id], state.known[id] = entry, entry, true
				lines[#lines + 1] = "/"
					.. id
					.. " "
					.. string.rep("  ", depth)
					.. encode(entry.name)
					.. (entry.directory and "/" or "")
				if entry.expandable and state.expanded[entry.path] then
					visit(entry.path, depth + 1)
				end
			end
		end
	end
	visit(state.root, 0)
	if #unchecked > 0 then
		local root = shared.find_git_root(state.root)
		if root and vim.fn.executable("git") == 1 then
			local tick = vim.api.nvim_buf_get_changedtick(buf)
			state.filtering = true
			vim.system(
				{ "git", "check-ignore", "-z", "--stdin" },
				{
					cwd = root,
					stdin = table.concat(unchecked, "\0") .. "\0",
				},
				vim.schedule_wrap(function(result)
					if states[buf] ~= state then
						return
					end
					state.filtering = nil
					if result.code > 1 then
						state.show_ignored = true
						vim.notify("Cannot filter Git ignored files: " .. (result.stderr or ""), vim.log.levels.WARN)
					else
						for _, path in ipairs(unchecked) do
							state.ignored[path] = false
						end
						for _, path in ipairs(vim.split(result.stdout or "", "\0", { plain = true, trimempty = true })) do
							state.ignored[path] = true
						end
					end
					-- Never replace listing edits made while Git was running.
					if vim.api.nvim_buf_get_changedtick(buf) == tick then
						render(buf)
					end
				end)
			)
			return
		end
		state.show_ignored = true
	end
	state.originals = originals
	if #lines == 0 then
		lines = { "" }
	end
	local changed = not vim.deep_equal(lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
	if changed then
		local undolevels, modifiable = vim.bo[buf].undolevels, vim.bo[buf].modifiable
		vim.bo[buf].modifiable, vim.bo[buf].undolevels = true, -1
		states[buf].rendering = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		states[buf].rendering = nil
		vim.bo[buf].undolevels, vim.bo[buf].modifiable = undolevels, modifiable
	end
	vim.bo[buf].modified = false
	draw_tree(buf, 0, vim.api.nvim_buf_line_count(buf))
	if changed then
		vim.api.nvim_exec_autocmds("User", { pattern = "NopackExplorerChanged", modeline = false })
	end
end
local function refresh(buf, files)
	local state = states[buf]
	if files then
		-- New-file events invalidate only cached parent listings, once per batch.
		local changed = false
		for path in pairs(files) do
			local directory = vim.fs.dirname(path)
			if state.children[directory] then
				state.children[directory], changed = nil, true
			end
			state.ignored[path] = nil
		end
		if not changed then
			return
		end
	else
		state.children, state.ignored = {}, {}
	end
	render(buf)
end

local function plan(buf)
	local state, rows, targets = states[buf], {}, {}
	local parsed, failure = tree_rows(buf)
	if failure then
		error(failure, 0)
	end
	for index = 1, vim.api.nvim_buf_line_count(buf) do
		local parsed_row = parsed[index]
		if parsed_row then
			local row = vim.tbl_extend("force", {}, parsed_row)
			row.source = row.id and (state.originals[row.id] or entries[row.id])
			row.source = row.source and vim.tbl_extend("force", {}, row.source)
			if row.id and not row.source then
				error("Unknown file ID: " .. row.id, 0)
			end
			if row.source and row.source.directory ~= row.directory then
				error("Keep the directory '/' marker", 0)
			end
			if targets[row.target] then
				error("Duplicate name; rename pasted entries before :w: " .. row.target, 0)
			end
			targets[row.target] = true
			rows[#rows + 1] = row
		end
	end
	local operations, retained = {}, {}
	-- An unchanged row owns the original; other rows with its ID are copies.
	for _, row in ipairs(rows) do
		if row.source and row.source.path == row.target then
			retained[row.id] = true
		end
	end
	for _, row in ipairs(rows) do
		if row.source then
			if row.source.path ~= row.target then
				row.kind = state.originals[row.id] and not retained[row.id] and "rename" or "copy"
				retained[row.id] = true
				operations[#operations + 1] = row
			end
		else
			row.kind = "create"
			operations[#operations + 1] = row
		end
	end
	for id, entry in pairs(state.originals) do
		if not retained[id] then
			operations[#operations + 1] = { kind = "delete", source = vim.tbl_extend("force", {}, entry) }
		end
	end
	-- A directory operation already owns its subtree. Never stage it twice.
	local source_dirs, target_dirs = {}, {}
	for _, op in ipairs(operations) do
		if op.source and op.source.directory then
			source_dirs[op.source.path] = op
		end
		if op.directory and op.target then
			target_dirs[op.target] = op
		end
	end
	local function ancestor(path, directories)
		local parent = vim.fs.dirname(path)
		while parent ~= path do
			if directories[parent] then
				return directories[parent]
			end
			path, parent = parent, vim.fs.dirname(parent)
		end
	end
	local filtered = {}
	for _, op in ipairs(operations) do
		local parent = op.source and ancestor(op.source.path, source_dirs)
		local covered = parent
			and (
				parent.kind == "delete" and op.kind == "delete"
				or parent.kind == "rename"
					and op.kind == "rename"
					and op.target == parent.target .. op.source.path:sub(#parent.source.path + 1)
			)
		local target_parent = op.target and ancestor(op.target, target_dirs)
		local moving_parent = op.target and ancestor(op.target, source_dirs)
		if
			parent and not covered
			or target_parent and target_parent.kind ~= "create" and not covered
			or moving_parent and moving_parent.kind ~= "copy" and not covered
		then
			error("Save folder changes separately from edits inside it", 0)
		end
		if not covered then
			filtered[#filtered + 1] = op
		end
	end
	operations = filtered
	-- Materialize missing parent folders as ordinary create operations in the same
	-- transaction, so cancellation and rollback cover the complete relative path.
	local directories, additions = {}, {}
	for _, op in ipairs(operations) do
		if op.target then
			local parent = vim.fs.dirname(op.target)
			while parent ~= state.root do
				if directories[parent] ~= nil then
					break
				end
				local stat = vim.uv.fs_stat(parent)
				if stat then
					if stat.type ~= "directory" then
						error("Parent is not a folder: " .. parent, 0)
					end
					directories[parent] = true
					break
				end
				if targets[parent] and not target_dirs[parent] then
					error("Parent is planned as a file: " .. parent, 0)
				end
				directories[parent] = true
				if not target_dirs[parent] then
					additions[#additions + 1] = { kind = "create", directory = true, target = parent }
				end
				parent = vim.fs.dirname(parent)
			end
		end
	end
	vim.list_extend(operations, additions)
	table.sort(operations, function(a, b)
		-- Install parent directories before their descendants.
		local ap, bp = a.target or a.source.path, b.target or b.source.path
		if #ap == #bp then
			return ap < bp
		end
		return #ap < #bp
	end)

	local buffers, parents = {}, {}
	for _, loaded in ipairs(vim.api.nvim_list_bufs()) do
		buffers[#buffers + 1] = {
			id = loaded,
			name = buffer_path(loaded, parents),
			modified = vim.bo[loaded].modified,
			directory = states[loaded] ~= nil,
		}
	end
	for _, op in ipairs(operations) do
		if op.source and stat_key(vim.uv.fs_lstat(op.source.path)) ~= op.source.key then
			error("File changed externally; refresh before editing: " .. op.source.path, 0)
		end
		if op.target then
			for _, buffer in ipairs(buffers) do
				local name = buffer.name
				if name == op.target or vim.startswith(name, op.target .. "/") then
					error("Destination already has an open buffer: " .. op.target, 0)
				end
			end
		end
		if op.target and vim.uv.fs_lstat(op.target) then
			error("Destination already exists: " .. op.target, 0)
		end
		if op.source and op.target and vim.startswith(op.target, op.source.path .. "/") then
			error("Cannot copy a directory inside itself", 0)
		end
		if op.kind == "delete" or op.kind == "rename" then
			for _, buffer in ipairs(buffers) do
				local name = buffer.name
				if
					buffer.modified
					and (op.kind == "delete" or buffer.directory)
					and (name == op.source.path or vim.startswith(name, op.source.path .. "/"))
				then
					error("Save or discard modified buffer first: " .. name, 0)
				end
			end
		end
	end
	return operations, buffers
end
local function commit(buf)
	local operations, buffers = plan(buf)
	if #operations == 0 then
		vim.bo[buf].modified = false
		return true
	end
	local summary = {}
	for _, op in ipairs(operations) do
		summary[#summary + 1] = op.kind
			.. " "
			.. (op.source and op.source.path or "")
			.. (op.target and " -> " .. op.target or "")
	end
	if vim.fn.confirm(table.concat(summary, "\n"), "&Apply\n&Cancel", 2) ~= 1 then
		return false
	end
	local stages = {}
	local ok, err = pcall(function()
		-- Stage every operation before removing originals or exposing destinations.
		for _, op in ipairs(operations) do
			if op.source and stat_key(vim.uv.fs_lstat(op.source.path)) ~= op.source.key then
				error("File changed during confirmation: " .. op.source.path, 0)
			end
			local parent = vim.fs.dirname(op.target or op.source.path)
			while not vim.uv.fs_stat(parent) do
				parent = vim.fs.dirname(parent)
			end
			op.stage = checked(vim.uv.fs_mkdtemp(parent .. "/.flash-XXXXXX"))
			op.item = vim.fs.joinpath(op.stage, "item")
			stages[#stages + 1] = op
			if op.kind == "copy" then
				op.mode = copy(op.source.path, op.item, true)
			elseif op.kind == "create" then
				if op.directory then
					checked(vim.uv.fs_mkdir(op.item, 493))
				else
					checked(vim.uv.fs_close(checked(vim.uv.fs_open(op.item, "wx", 420))))
				end
			end
		end
		local _, current_buffers = plan(buf) -- recheck after asynchronous staging
		buffers = current_buffers
		for _, op in ipairs(stages) do
			if op.kind == "rename" or op.kind == "delete" then
				if stat_key(vim.uv.fs_lstat(op.source.path)) ~= op.source.key then
					error("File changed during save: " .. op.source.path, 0)
				end
				checked(vim.uv.fs_rename(op.source.path, op.item))
				op.moved = true
			end
		end
		for _, op in ipairs(stages) do
			if op.target then
				if vim.uv.fs_lstat(op.target) then
					error("Destination appeared during save: " .. op.target, 0)
				end
				checked(vim.uv.fs_rename(op.item, op.target))
				op.installed = true
			end
		end
	end)
	if not ok then
		local recovery = {}
		for i = #stages, 1, -1 do
			local op = stages[i]
			local rollback_ok = true
			if op.installed then
				rollback_ok = vim.uv.fs_rename(op.target, op.item) ~= nil
			end
			if rollback_ok and op.moved then
				rollback_ok = not vim.uv.fs_lstat(op.source.path) and vim.uv.fs_rename(op.item, op.source.path) ~= nil
			end
			op.rollback_ok = rollback_ok
			if not rollback_ok then
				recovery[#recovery + 1] = op.stage
			end
		end
		-- Restore every original before yielding to asynchronous cleanup.
		for _, op in ipairs(stages) do
			if op.rollback_ok and not pcall(remove, op.stage) then
				recovery[#recovery + 1] = op.stage
			end
		end
		error(tostring(err) .. (#recovery > 0 and "\nRecover files from: " .. table.concat(recovery, "\n") or ""), 0)
	end
	for _, op in ipairs(stages) do
		if op.mode then
			local chmod_ok, chmod_err = vim.uv.fs_chmod(op.target, op.mode)
			if not chmod_ok then
				vim.notify("Copied, but could not restore directory permissions: " .. chmod_err, vim.log.levels.WARN)
			end
		end
		if op.kind == "rename" then
			for _, buffer in ipairs(buffers) do
				local loaded = buffer.id
				local directory = states[loaded]
				local name = buffer.name
				if name == op.source.path or vim.startswith(name, op.source.path .. "/") then
					local destination = op.target .. name:sub(#op.source.path + 1)
					if directory then
						directory.root = destination
						for _, win in ipairs(vim.fn.win_findbuf(loaded)) do
							vim.wo[win][0].winbar = destination:gsub("%%", "%%%%")
						end
					end
					vim.api.nvim_buf_set_name(loaded, (directory and "flash://" or "") .. destination)
					buffer.name = destination
				end
			end
			local moved = {}
			if op.source.directory then
				for path, id in pairs(ids) do
					if path == op.source.path or vim.startswith(path, op.source.path .. "/") then
						moved[path] = id
					end
				end
			else
				moved[op.source.path] = ids[op.source.path]
			end
			for path, id in pairs(moved) do
				local destination = op.target .. path:sub(#op.source.path + 1)
				ids[path], ids[destination] = nil, id
				entries[id].path = destination
				entries[id].name = vim.fs.basename(destination)
			end
		end
	end
	for _, state in pairs(states) do
		for _, op in ipairs(stages) do
			if op.kind == "rename" and op.source.directory then
				local moved = {}
				for path, expanded in pairs(state.expanded) do
					if path == op.source.path or vim.startswith(path, op.source.path .. "/") then
						moved[op.target .. path:sub(#op.source.path + 1)] = expanded
						state.expanded[path] = nil
					end
				end
				state.expanded = vim.tbl_extend("force", state.expanded, moved)
			end
		end
		state.children = {}
	end
	local deleted = {}
	for _, buffer in ipairs(buffers) do
		for _, op in ipairs(stages) do
			if
				op.kind == "delete"
				and (buffer.name == op.source.path or vim.startswith(buffer.name, op.source.path .. "/"))
			then
				deleted[buffer.id] = true
				break
			end
		end
	end
	local replacement
	if next(deleted) then
		for _, candidate in ipairs(shared.buffers()) do
			if not deleted[candidate] and require("buffer_policy").is_source(candidate) then
				replacement = candidate
				break
			end
		end
		for candidate in pairs(deleted) do
			if vim.api.nvim_buf_is_valid(candidate) then
				if vim.bo[candidate].modified then
					vim.notify(
						"Deleted file has unsaved buffer; kept: " .. vim.api.nvim_buf_get_name(candidate),
						vim.log.levels.WARN
					)
				else
					if not replacement and #vim.fn.win_findbuf(candidate) > 0 then
						replacement = vim.api.nvim_create_buf(true, false)
					end
					shared.delete_buffer(candidate, false, replacement)
				end
			end
		end
	end
	for _, op in ipairs(stages) do
		local removed, failure = pcall(remove, op.stage)
		if not removed then
			vim.notify("Could not remove staging directory: " .. op.stage .. "\n" .. failure, vim.log.levels.WARN)
		end
	end
	if states[buf] and vim.api.nvim_buf_is_valid(buf) then
		refresh(buf)
	end
	for candidate, state in pairs(states) do
		if candidate ~= buf and not vim.bo[candidate].modified and vim.fn.isdirectory(state.root) == 1 then
			-- Only refresh directories directly affected by this explicit save.
			for _, op in ipairs(stages) do
				if
					op.kind == "rename" and (state.root == op.target or vim.startswith(state.root, op.target .. "/"))
				then
					refresh(candidate)
					break
				end
			end
		end
	end
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf, modeline = false })
	end
	return true
end
local function save(buf, callback)
	if states[buf].filtering then
		vim.notify("Git ignore filtering in progress", vim.log.levels.INFO)
		return
	end
	if saving then
		vim.notify("A directory save is already running", vim.log.levels.WARN)
		return
	end
	saving = buf
	locks = {}
	for candidate in pairs(states) do
		locks[candidate] = vim.bo[candidate].modifiable
		vim.bo[candidate].modifiable = false
	end
	local thread = coroutine.create(function()
		local ok, result = pcall(commit, buf)
		saving = nil
		for candidate, value in pairs(locks) do
			if vim.api.nvim_buf_is_valid(candidate) then
				vim.bo[candidate].modifiable = value
			end
		end
		locks = nil
		-- A hidden modified listing survives; completed, unused listings do not.
		for candidate in pairs(states) do
			if not vim.bo[candidate].modified and #vim.fn.win_findbuf(candidate) == 0 then
				vim.api.nvim_buf_delete(candidate, { force = true })
			end
		end
		if not ok then
			vim.notify(result, vim.log.levels.ERROR)
		end
		if callback and vim.api.nvim_buf_is_valid(buf) then
			callback(ok and result)
		end
	end)
	local ok, failure = coroutine.resume(thread)
	if not ok then
		vim.notify(failure, vim.log.levels.ERROR)
	end
end
local function clean(buf, action)
	if states[buf].filtering then
		vim.notify("Git ignore filtering in progress", vim.log.levels.INFO)
		return
	end
	if saving then
		vim.notify("Directory save in progress", vim.log.levels.WARN)
		return
	end
	if not vim.bo[buf].modified then
		return action(false, false)
	end
	local win = vim.api.nvim_get_current_win()
	local choice = vim.fn.confirm("Unsaved directory edits", "&Save\n&Discard\n&Cancel", 3)
	if choice == 1 then
		return save(buf, function(saved)
			if saved and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
				if vim.api.nvim_get_current_win() == win then
					action(true, false)
				else
					vim.api.nvim_win_call(win, function()
						action(true, false)
					end)
				end
			end
		end)
	end
	if choice == 2 then
		refresh(buf)
		return action(true, true)
	end
end

local function style_window(win)
	local buf = vim.api.nvim_win_get_buf(win)
	if states[buf] then
		if not window_options[win] then
			local saved = {}
			for _, name in ipairs(ui_options) do
				saved[name] = vim.wo[win][name]
			end
			-- A split inherits the explorer's temporary options, not editor defaults.
			for origin, options in pairs(window_options) do
				if vim.api.nvim_win_is_valid(origin) and vim.api.nvim_win_get_buf(origin) == buf then
					saved = vim.deepcopy(options)
					break
				end
			end
			window_options[win] = saved
		end
		vim.wo[win][0].conceallevel = 3
		vim.wo[win][0].concealcursor = "nvic"
		vim.wo[win][0].wrap = false
		vim.wo[win][0].foldenable = false
		vim.wo[win][0].spell = false
		vim.wo[win][0].cursorcolumn = false
		vim.wo[win][0].list = false
		vim.wo[win][0].winbar = states[buf].root:gsub("%%", "%%%%")
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
		local prefix = line:match("^/%d+ *")
		if prefix and cursor[2] < #prefix then
			vim.api.nvim_win_set_cursor(win, { cursor[1], #prefix })
		end
	elseif window_options[win] then
		restore_window(win, window_options[win])
		window_options[win] = nil
	end
end
vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
	group = group,
	callback = function()
		style_window(vim.api.nvim_get_current_win())
	end,
})
vim.api.nvim_create_autocmd("WinClosed", {
	group = group,
	callback = function(args)
		local closed = tonumber(args.match)
		window_options[closed] = nil
		for buf, state in pairs(states) do
			if state.help and state.help.owner == closed then
				close_help(buf)
			elseif state.help and state.help.win == closed then
				state.help = nil
			end
		end
	end,
})

function M.open(root, sidebar, file)
	root = vim.uv.fs_realpath(root) or vim.fs.normalize(root)
	if vim.fn.isdirectory(root) ~= 1 then
		error("Not a directory: " .. root, 0)
	end
	local previous = vim.api.nvim_get_current_buf()
	local origin = vim.api.nvim_get_current_win()
	local saved = vim.deepcopy(window_options[origin] or {})
	if not window_options[origin] then
		for _, name in ipairs(ui_options) do
			saved[name] = vim.wo[origin][name]
		end
	end
	if states[previous] and vim.bo[previous].modified then
		clean(previous, function()
			M.open(root, sidebar, file)
		end)
		return
	end
	local buf
	for candidate, state in pairs(states) do
		if state.root == root then
			buf = candidate
			break
		end
	end
	if not buf then
		buf = vim.api.nvim_create_buf(false, false)
		states[buf] = {
			root = root,
			originals = {},
			known = {},
			children = {},
			expanded = {},
			hidden = true,
			show_ignored = true,
			ignored = {},
			sort = "name",
			reverse = false,
		}
		vim.api.nvim_buf_set_name(buf, "flash://" .. root)
		vim.bo[buf].buftype = "acwrite"
		vim.bo[buf].bufhidden = "hide"
		vim.bo[buf].swapfile = false
		vim.bo[buf].undofile = false
		vim.bo[buf].filetype = "flash-explorer"
		vim.api.nvim_buf_call(buf, function()
			vim.cmd([[syntax match FlashDirectoryId /^\/\d\+ / conceal]])
			vim.cmd([[syntax match FlashDirectoryFolder /.*\/$/ contains=FlashDirectoryId]])
			vim.cmd("highlight default link FlashDirectoryFolder Directory")
		end)
		local function map(key, fn, desc)
			vim.keymap.set("n", key, fn, { buffer = buf, silent = true, desc = desc })
		end
		-- Keep hidden identity columns when replacing an entire filename.
		for key, action in pairs({ ["0"] = "", ["^"] = "", ["<Home>"] = "", I = "i", cc = "C", S = "C" }) do
			vim.keymap.set("n", key, function()
				local prefix = vim.fn.getline("."):match("^/%d+ *") or ""
				return "0" .. (#prefix > 0 and #prefix .. "l" or "") .. action
			end, { buffer = buf, expr = true, desc = "Edit filename without its ID" })
		end
		for _, key in ipairs({ "p", "P" }) do
			map(key, function()
				local index = vim.fn.line(".")
				local row = tree_rows(buf)[index]
				local register, count = vim.v.register, vim.v.count1
				if vim.fn.getregtype(register):sub(1, 1) ~= "V" then
					vim.cmd.normal({ args = { '"' .. register .. count .. key }, bang = true })
					return
				end
				local contents = vim.fn.getreg(register, 1, true)
				local first = contents[1] or ""
				local label = first:match("^/%d+ (.*)$") or first
				local depth = #(label:match("^ *") or "") / 2
				local delta = (row and row.depth or 0) - depth
				if key == "p" and row and row.directory then
					local rows = tree_rows(buf)
					while rows[index + 1] and rows[index + 1].depth > row.depth do
						index = index + 1
					end
					vim.api.nvim_win_set_cursor(0, { index, 0 })
				end
				vim.cmd.normal({ args = { '"' .. register .. count .. key }, bang = true })
				if delta == 0 then
					return
				end
				local start = key == "p" and index or index - 1
				local lines = vim.api.nvim_buf_get_lines(buf, start, start + #contents * count, false)
				for i, line in ipairs(lines) do
					local prefix, text = line:match("^(/%d+ )(.*)$")
					prefix, text = prefix or "", text or line
					local indent, name = text:match("^( *)(.*)$")
					lines[i] = prefix .. string.rep(" ", math.max(0, #indent + delta * 2)) .. name
				end
				vim.cmd("undojoin")
				vim.api.nvim_buf_set_lines(buf, start, start + #lines, false, lines)
			end, "Paste entries at current tree depth")
		end
		for _, key in ipairs({ "o", "O" }) do
			vim.keymap.set("n", key, function()
				if states[buf].filtering or not vim.bo[buf].modifiable then
					return
				end
				local index = vim.fn.line(".")
				local row = tree_rows(buf)[index]
				local depth = row and row.depth or 0
				if key == "o" and row and row.directory then
					depth = depth + 1
					local collapsed = not states[buf].expanded[row.target]
					states[buf].expanded[row.target] = true
					-- Existing clean folders can expand before editing. Pending rows
					-- stay untouched; their children appear after the save.
					if collapsed and row.id and not vim.bo[buf].modified then
						render(buf)
					end
				end
				index = index - (key == "O" and 1 or 0)
				vim.api.nvim_buf_set_lines(buf, index, index, false, { string.rep(" ", depth * 2) })
				vim.api.nvim_win_set_cursor(0, { index + 1, depth * 2 })
				vim.cmd("startinsert!")
			end, { buffer = buf, desc = "Create entry (o on a folder creates a child)" })
		end
		vim.keymap.set("i", "<BS>", function()
			local prefix = vim.fn.getline("."):match("^/%d+ *")
			return prefix and vim.fn.col(".") <= #prefix + 1 and "" or "<BS>"
		end, { buffer = buf, expr = true })
		local function open(command)
			local line = vim.fn.getline(".")
			local path = M.path(buf, line, vim.fn.line("."))
			local id = tonumber(line:match("^/(%d+) "))
			local original = id and entries[id] and entries[id].path
			if not path then
				return
			end
			clean(buf, function(_, discarded)
				if discarded then
					path = original
				end
				if not path then
					return
				end
				if not vim.uv.fs_lstat(path) then
					vim.notify("Entry does not exist; save directory edits first: " .. path, vim.log.levels.WARN)
					return
				end
				if command then
					local saved = window_options[vim.api.nvim_get_current_win()]
					vim.cmd(command)
					restore_window(vim.api.nvim_get_current_win(), saved)
				end
				if vim.fn.isdirectory(path) == 1 then
					if not command and id and entries[id].expandable then
						states[buf].expanded[path] = not states[buf].expanded[path]
						render(buf)
					else
						M.open(path)
					end
				else
					focus_editor()
					vim.cmd("edit " .. vim.fn.fnameescape(path))
				end
			end)
		end
		map("<CR>", function()
			open()
		end, "Open file / expand or collapse folder")
		map("za", function()
			open()
		end, "Open file / expand or collapse folder")
		map("zc", function()
			clean(buf, function()
				local row = tree_rows(buf)[vim.fn.line(".")]
				if not row then
					return
				end
				local path = states[buf].expanded[row.target] and row.target or vim.fs.dirname(row.target)
				if path == states[buf].root then
					return
				end
				states[buf].expanded[path] = nil
				render(buf)
				for index, item in pairs(tree_rows(buf)) do
					if item.target == path then
						vim.api.nvim_win_set_cursor(0, { index, 0 })
						break
					end
				end
			end)
		end, "Collapse folder / parent")
		for key, cmd in pairs({
			["<localleader>v"] = "belowright vnew",
			["<localleader>s"] = "belowright new",
			["<localleader>t"] = "tabnew",
		}) do
			map(key, function()
				open(cmd)
			end, "Open in split / tab")
		end
		map("-", function()
			M.open(vim.fs.dirname(states[buf].root))
		end, "Parent directory")
		map("<localleader>w", function()
			M.open(vim.fn.getcwd())
		end, "Working directory")
		map("gr", function()
			clean(buf, function(refreshed)
				if not refreshed then
					refresh(buf)
				end
			end)
		end, "Refresh directory")
		map("g.", function()
			clean(buf, function()
				states[buf].hidden = not states[buf].hidden
				refresh(buf)
			end)
		end, "Toggle hidden files")
		map("<localleader>i", function()
			clean(buf, function()
				states[buf].show_ignored = not states[buf].show_ignored
				render(buf)
			end)
		end, "Toggle Git ignored files")
		for key, cmd in pairs({ ["<localleader>d"] = "cd", ["<localleader>D"] = "tcd" }) do
			map(key, function()
				vim.cmd(cmd .. " " .. vim.fn.fnameescape(states[buf].root))
			end, "Change working directory")
		end
		map("gx", function()
			local path = M.path(buf, vim.fn.getline("."), vim.fn.line("."))
			if path then
				vim.ui.open(path)
			end
		end, "Open externally")
		map("<C-c>", function()
			clean(buf, function()
				local win = vim.api.nvim_get_current_win()
				focus_editor()
				vim.api.nvim_win_close(win, false)
			end)
		end, "Close explorer")
		map("gs", function()
			clean(buf, function()
				vim.ui.select({ "name", "size", "mtime" }, { prompt = "Sort by" }, function(column)
					if not column then
						return
					end
					vim.ui.select({ "ascending", "descending" }, { prompt = "Sort order" }, function(order)
						if order and states[buf] and not vim.bo[buf].modified then
							states[buf].sort = column
							states[buf].reverse = order == "descending"
							refresh(buf)
						end
					end)
				end)
			end)
		end, "Choose sort order")
		map("<localleader>p", function()
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.wo[win].previewwindow then
					vim.api.nvim_win_close(win, false)
					return
				end
			end
			local path = M.path(buf, vim.fn.getline("."), vim.fn.line("."))
			if path and vim.fn.filereadable(path) == 1 then
				local saved = window_options[vim.api.nvim_get_current_win()]
				vim.cmd("pedit " .. vim.fn.fnameescape(path))
				for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
					if vim.wo[win].previewwindow then
						restore_window(win, saved)
					end
				end
			end
		end, "Toggle preview")
		map("g?", function()
			if states[buf].help then
				close_help(buf)
				return
			end
			local owner = vim.api.nvim_get_current_win()
			local help = vim.api.nvim_create_buf(false, true)
			local items = {
				{ "Navigation" },
				{ "Enter / za", "Open file or expand/collapse folder" },
				{ "zc", "Collapse folder or its parent" },
				{ "- / Local w", "Root parent / working directory" },
				{ "Local v / Local s", "Open in vertical / horizontal split" },
				{ "Local t", "Open in a new tab" },
				{ "Local p", "Toggle file preview" },
				{ "Ctrl-c", "Close explorer, return to editor" },
				{},
				{ "File operations  (apply with :w)" },
				{ "yy / p", "Copy entry; rename pasted row" },
				{ "i / a", "Edit name here / after the cursor" },
				{ "I / A", "Edit at filename start / end" },
				{ "cc", "Replace the entire filename" },
				{ "o / O", "Create entry below / above" },
				{ "name / name/", "Create a file / folder" },
				{ "test/main.py", "Create missing folders and the file" },
				{ "dd", "Delete entry; collapse folder first" },
				{ ":w", "Review and confirm file operations" },
				{},
				{ "View" },
				{ "gr", "Refresh directory contents" },
				{ "g. / Local i", "Toggle hidden / Git ignored files" },
				{ "gs", "Choose sort order" },
				{ "Local d / Local D", "Set global / tab working directory" },
				{ "gx", "Open in an external application" },
				{},
				{ "Notes" },
				{ "  Edit names normally; Esc ends editing, :w applies." },
				{ "  Example: o, src/, Esc, :w creates the src folder." },
				{ "  On a folder row, o creates a child automatically." },
				{ "  Keep / when renaming folders. Paths are relative." },
				{ "  New folders and their files can be saved together." },
				{ "  Save folder renames/deletes separately from child edits." },
				{ "  Rename duplicate entries before saving." },
				{},
				{ "g?", "Toggle guide from the tree or guide" },
				{ "q / Esc", "Close while focused in the guide" },
			}
			local lines, width = {}, 0
			local localleader = vim.g.maplocalleader or "\\"
			for index, item in ipairs(items) do
				if item[2] then
					item[1] = item[1]:gsub("Local ([%a])", function(key)
						return localleader .. key
					end)
				end
				lines[index] = item[2] and string.format("  %-16s  %s", item[1], item[2])
					or item[1] and "  " .. item[1]
					or ""
				width = math.max(width, vim.fn.strdisplaywidth(lines[index]) + 2)
			end
			vim.api.nvim_buf_set_lines(help, 0, -1, false, lines)
			for index, item in ipairs(items) do
				if item[1] then
					vim.api.nvim_buf_set_extmark(help, tree_ns, index - 1, 2, {
						end_col = item[2] and 2 + #item[1] or #lines[index],
						hl_group = item[2] and "Special" or item[1]:sub(1, 1) == " " and "Comment" or "Title",
					})
				end
			end
			vim.bo[help].modifiable = false
			vim.bo[help].bufhidden = "wipe"
			width = math.min(width, vim.o.columns - 4)
			local height = math.min(#lines, vim.o.lines - 4)
			local win = vim.api.nvim_open_win(help, true, {
				relative = "editor",
				style = "minimal",
				border = "single",
				title = " FLASH Explorer ",
				title_pos = "center",
				width = width,
				height = height,
				row = math.floor((vim.o.lines - height) / 2),
				col = math.floor((vim.o.columns - width) / 2),
			})
			vim.wo[win].wrap = true
			vim.wo[win].winfixbuf = true
			states[buf].help = { win = win, buf = help, owner = owner }
			for _, key in ipairs({ "g?", "q", "<Esc>", "<C-c>" }) do
				vim.keymap.set("n", key, function()
					close_help(buf)
				end, { buffer = help })
			end
		end, "Directory help")
		vim.api.nvim_create_autocmd("BufWriteCmd", {
			group = group,
			buffer = buf,
			callback = function()
				save(buf)
			end,
		})
		vim.api.nvim_buf_attach(buf, false, {
			on_lines = function(_, changed, _, first, old_last, last)
				local state = states[changed]
				if not state or state.rendering then
					return
				end
				-- Undo restores old extmarks after on_lines. Draw after the edit
				-- completes, merging changed ranges without timers or cursor work.
				local pending = state.redraw
				if pending then
					pending.first = math.min(pending.first, first)
					pending.last = math.max(pending.last + last - old_last, last + 1)
					return
				end
				state.redraw = { first = first, last = last + 1 }
				vim.schedule(function()
					if states[changed] ~= state then
						return
					end
					local range = state.redraw
					state.redraw = nil
					local count = vim.api.nvim_buf_line_count(changed)
					draw_tree(changed, math.min(range.first, count - 1), math.min(range.last, count))
				end)
			end,
		})
		vim.api.nvim_create_autocmd("TextYankPost", {
			group = group,
			buffer = buf,
			callback = function()
				for _, line in ipairs(vim.v.event.regcontents) do
					local id = tonumber(line:match("^/(%d+) "))
					if id and entries[id] then
						copied_ids[id] = true
					end
				end
			end,
		})
		vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
			group = group,
			buffer = buf,
			callback = function()
				local prefix = vim.fn.getline("."):match("^/%d+ *")
				local cursor = vim.api.nvim_win_get_cursor(0)
				if prefix and cursor[2] < #prefix then
					vim.api.nvim_win_set_cursor(0, { cursor[1], #prefix })
				end
			end,
		})
	end
	if file and file ~= "" then
		local parent = vim.uv.fs_realpath(vim.fs.dirname(file))
		file = parent and vim.fs.joinpath(parent, vim.fs.basename(file)) or file
		if vim.startswith(file, root:gsub("/+$", "") .. "/") then
			while parent and parent ~= root do
				states[buf].expanded[parent] = true
				parent = vim.fs.dirname(parent)
			end
		end
	end
	if not vim.bo[buf].modified then
		refresh(buf) -- navigation/reopening is an explicit filesystem refresh
	end
	if saving and locks[buf] == nil then
		locks[buf] = vim.bo[buf].modifiable
		vim.bo[buf].modifiable = false
	end
	if sidebar then
		local win = vim.api.nvim_open_win(buf, true, { split = "left", win = 0, width = shared.sidebar_width() })
		window_options[win] = saved
		shared.fix_sidebar_width(win)
	else
		vim.api.nvim_set_current_buf(buf)
	end
	style_window(vim.api.nvim_get_current_win())
	if file and not states[buf].filtering then
		for index, row in pairs(tree_rows(buf)) do
			if row.target == file then
				local line = vim.api.nvim_buf_get_lines(buf, index - 1, index, false)[1]
				vim.api.nvim_win_set_cursor(0, { index, #(line:match("^/%d+ *") or "") })
				break
			end
		end
	end
	return buf
end
vim.api.nvim_create_autocmd("BufWipeout", {
	group = group,
	callback = function(args)
		local state = states[args.buf]
		close_help(args.buf)
		states[args.buf] = nil
		if state then
			for id in pairs(state.known) do
				local retained = copied_ids[id]
				for _, other in pairs(states) do
					retained = retained or other.known[id]
				end
				if not retained and entries[id] then
					local path = entries[id].path
					entries[id] = nil
					if ids[path] == id then
						ids[path] = nil
					end
				end
			end
		end
	end,
})
vim.api.nvim_create_autocmd("BufHidden", {
	group = group,
	callback = function(args)
		if not states[args.buf] then
			return
		end
		close_help(args.buf)
		-- Defer disposal until all listeners have finished using the event's ID.
		vim.schedule(function()
			if
				not saving
				and states[args.buf]
				and not vim.bo[args.buf].modified
				and #vim.fn.win_findbuf(args.buf) == 0
			then
				vim.api.nvim_buf_delete(args.buf, { force = true })
			end
		end)
	end,
})
function M.refresh(buf, files)
	if not saving and states[buf] and not vim.bo[buf].modified then
		refresh(buf, files)
	end
end
vim.api.nvim_create_autocmd("BufEnter", {
	group = group,
	callback = function(args)
		if states[args.buf] then
			return
		end
		local name = vim.api.nvim_buf_get_name(args.buf)
		if vim.bo[args.buf].buftype == "" and name ~= "" and vim.fn.isdirectory(name) == 1 then
			vim.bo[args.buf].buflisted = false
			vim.bo[args.buf].buftype = "nofile"
			if vim.g.SessionLoad then
				return -- Session restoration owns cleanup; do not open or scan a tree.
			end
			M.open(name)
			-- BufEnter listeners still receive the original ID; dispose after dispatch.
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(args.buf) and #vim.fn.win_findbuf(args.buf) == 0 then
					vim.api.nvim_buf_delete(args.buf, { force = true })
				end
			end)
		end
	end,
})
vim.api.nvim_create_autocmd("User", {
	group = group,
	pattern = "NopackFilesCreated",
	callback = function(args)
		for buf in pairs(states) do
			M.refresh(buf, args.data.files)
		end
	end,
})
return M
