-- Explicit, single-buffer collaboration. No polling or external server process.
-- An authenticated TCP session orders edits; text operations rebase concurrent changes.
-- A sidecar next to the source (usually on NFS) advertises the session to later openers.
local op = require("peerpad.operation")
local policy = require("peerpad.buffer")
local M = {}
local server, client
local group = vim.api.nvim_create_augroup("peerpad-transport", { clear = true })
local limit = 1024 * 1024
local cursor_ns = vim.api.nvim_create_namespace("peerpad-cursors")
-- Peers cycle through these; colorschemes may override LiveSharePeer1..6.
for i, link in ipairs({
	"DiagnosticVirtualTextInfo",
	"DiagnosticVirtualTextHint",
	"DiagnosticVirtualTextWarn",
	"DiagnosticVirtualTextOk",
	"DiagnosticVirtualTextError",
	"Visual",
}) do
	vim.api.nvim_set_hl(0, "LiveSharePeer" .. i, { link = link, default = true })
end

local function notify(message, level)
	vim.notify("Peerpad: " .. message, level or vim.log.levels.INFO)
end

local function close(handle)
	if handle and not handle:is_closing() then
		handle:close()
	end
end

-- One JSON frame per line. Bound both receive frames and outstanding socket writes.
local function channel(socket, receive, disconnected)
	local connection = { socket = socket, input = "", closed = false }
	function connection:stop(reason)
		if self.closed then
			return
		end
		self.closed = true
		self:settle()
		close(socket)
		if disconnected then
			disconnected(reason)
		end
	end
	-- One-shot limit for connecting/authenticating; cleared once the handshake completes.
	function connection:deadline(ms, reason)
		self:settle()
		self.timer = vim.uv.new_timer()
		self.timer:start(
			ms,
			0,
			vim.schedule_wrap(function()
				self:stop(reason)
			end)
		)
	end
	function connection:settle()
		close(self.timer)
		self.timer = nil
	end
	function connection:send(message)
		if self.closed then
			return
		end
		local frame = vim.json.encode(message) .. "\n"
		if socket:get_write_queue_size() + #frame > 4 * limit then
			self:stop("Connection cannot keep up; local text was retained")
			return
		end
		local request, err = socket:write(
			frame,
			vim.schedule_wrap(function(write_error)
				if write_error then
					self:stop(write_error)
				end
			end)
		)
		if not request then
			self:stop(err)
		end
	end
	function connection:read()
		local started, start_error = socket:read_start(vim.schedule_wrap(function(err, data)
			if self.closed then
				return
			end
			if err or not data then
				self:stop(err or "Connection closed by peer")
				return
			end
			self.input = self.input .. data
			while true do
				local finish = self.input:find("\n", 1, true)
				if not finish then
					if #self.input > 2 * limit then
						self:stop("Frame is too large")
					end
					return
				end
				if finish > 2 * limit then
					self:stop("Frame is too large")
					return
				end
				local frame = self.input:sub(1, finish - 1)
				self.input = self.input:sub(finish + 1)
				local ok, message = pcall(vim.json.decode, frame)
				if ok and type(message) == "table" then
					ok, message = pcall(receive, self, message)
				else
					ok, message = false, "Invalid message"
				end
				if not ok then
					self:stop(tostring(message))
				end
				if self.closed then
					return
				end
			end
		end))
		if not started then
			self:stop(start_error)
		end
	end
	return connection
end

local function disk_content(path)
	local stat = vim.uv.fs_stat(path)
	if stat and stat.size > 2 * limit then
		return false
	end
	if vim.fn.filereadable(path) == 0 then
		return nil
	end
	return table.concat(vim.fn.readfile(path, "b"), "\n")
end

local function document_valid(text)
	assert(#text <= limit and text:sub(-1) == "\n", "Invalid shared document")
end

-- Sidecar: `.<name>.flash-share` beside the source. Anyone allowed to write the
-- source may read it and join; it is never world-readable unless the source is
-- world-writable. Keep this name in sync with the discovery autocmd in init.lua.
local function sidecar_path(path)
	return vim.fs.joinpath(vim.fs.dirname(path), "." .. vim.fs.basename(path) .. ".flash-share")
end

local function printable(value, length)
	return (tostring(value):gsub("[%c]", "?"):sub(1, length or 64))
end

local function read_sidecar(file)
	local stat = vim.uv.fs_lstat(file)
	if not stat or stat.type ~= "file" or stat.size > 4096 then
		return nil
	end
	local fd = vim.uv.fs_open(file, "r", 0)
	if not fd then
		return nil
	end
	-- Refuse a symlink swapped in after lstat.
	local opened = vim.uv.fs_fstat(fd)
	local data = opened and opened.ino == stat.ino and opened.dev == stat.dev and vim.uv.fs_read(fd, 4096, 0)
	vim.uv.fs_close(fd)
	local ok, info = pcall(vim.json.decode, data or "")
	if
		not ok
		or type(info) ~= "table"
		or info.protocol ~= 1
		or type(info.token) ~= "string"
		or not info.token:match("^" .. ("%x"):rep(64) .. "$")
		or type(info.port) ~= "number"
		or info.port ~= math.floor(info.port)
		or info.port < 1
		or info.port > 65535
		or type(info.hosts) ~= "table"
		or #info.hosts > 32
	then
		return nil
	end
	for _, host in ipairs(info.hosts) do
		if type(host) ~= "string" or #host > 255 or not host:match("^[%w%.:%-_]+$") then
			return nil
		end
	end
	info.uid, info.user, info.host = stat.uid, printable(info.user), printable(info.host)
	return info
end

-- Only a sidecar written on this host can be proven stale.
local function stale(info)
	if info.host ~= vim.uv.os_gethostname() or type(info.pid) ~= "number" then
		return false
	end
	local alive, err = vim.uv.kill(info.pid, 0)
	return not alive and tostring(err):find("ESRCH") ~= nil
end

local function advertised(bind)
	if bind ~= "0.0.0.0" and bind ~= "::" then
		return { bind }
	end
	local hosts = { vim.uv.os_gethostname() }
	for _, addresses in pairs(vim.uv.interface_addresses()) do
		for _, address in ipairs(addresses) do
			if
				not address.internal
				and (
					address.family == "inet"
					or (bind == "::" and address.family == "inet6" and not address.ip:find("^fe80"))
				)
			then
				hosts[#hosts + 1] = address.ip
			end
		end
	end
	return hosts
end

-- Credentials must never be staged. Protect discovery files locally, once at startup.
local function exclude_sidecar(file, temp)
	local directory = vim.fs.dirname(file)
	if not vim.fs.find(".git", { path = directory, upward = true })[1] then
		return
	end
	assert(vim.fn.executable("git") == 1, "Git is required to exclude the session token")
	local function git(args)
		return vim.system(vim.list_extend({ "git", "-C", directory }, args), { text = true }):wait(2000)
	end
	local result = git({ "rev-parse", "--git-path", "info/exclude" })
	assert(result.code == 0, "Cannot locate Git's local exclude file")
	local path = vim.trim(result.stdout)
	if path:sub(1, 1) ~= "/" then
		path = vim.fs.joinpath(directory, path)
	end
	local lines = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
	local missing = {}
	for _, pattern in ipairs({ ".*.flash-share", ".*.flash-share.*" }) do
		if not vim.tbl_contains(lines, pattern) then
			missing[#missing + 1] = pattern
		end
	end
	if #missing > 0 then
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		-- Start a new line even when an existing exclude file has no final newline.
		assert(vim.fn.writefile(vim.list_extend({ "" }, missing), path, "a") == 0, "Cannot exclude session tokens")
	end
	for _, candidate in ipairs({ file, temp }) do
		assert(
			git({ "check-ignore", "-q", "--", candidate }).code == 0,
			"Session file is tracked or not safely ignored"
		)
	end
end

local function publish(owner, bind)
	local stat = assert(vim.uv.fs_stat(owner.path), "Save the source file before sharing")
	local perm = stat.mode % 512
	local readable_by_group = bit.band(perm, 16) ~= 0 -- group may write the source
	local mode = 384 + (readable_by_group and 32 or 0) + (bit.band(perm, 2) ~= 0 and 4 or 0)
	local file = sidecar_path(owner.path)
	local existing = read_sidecar(file)
	if existing then
		if not (stale(existing) and existing.uid == vim.uv.getuid()) then
			return false, existing.user .. "@" .. existing.host .. " is already sharing this file; use :PeerpadJoin"
		end
		vim.uv.fs_unlink(file)
	end
	local temp = file .. "." .. vim.fn.sha256(vim.uv.random(16)):sub(1, 16)
	exclude_sidecar(file, temp)
	local info = vim.json.encode({
		protocol = 1,
		port = owner.port,
		token = owner.token,
		hosts = advertised(bind),
		host = vim.uv.os_gethostname(),
		user = vim.uv.os_get_passwd().username,
		pid = vim.uv.os_getpid(),
	})
	-- Write privately under a random name, then link: creation is exclusive and
	-- readers never see a partial file. O_EXCL does not follow planted symlinks.
	local fd = assert(vim.uv.fs_open(temp, "wx", 384))
	local ok, err = pcall(function()
		if readable_by_group and stat.gid ~= vim.uv.getgid() then
			if not vim.uv.fs_fchown(fd, vim.uv.getuid(), stat.gid) then
				notify("Cannot give the share file the source's group; group members cannot join", vim.log.levels.WARN)
			end
		end
		assert(vim.uv.fs_fchmod(fd, mode))
		assert(vim.uv.fs_write(fd, info, 0) == #info, "Incomplete session file write")
	end)
	vim.uv.fs_close(fd)
	if ok then
		ok, err = vim.uv.fs_link(temp, file)
		-- NFS may report a retransmitted, successful link as failed.
		local linked = vim.uv.fs_lstat(temp)
		ok = ok or (linked and linked.nlink == 2)
	end
	vim.uv.fs_unlink(temp)
	if not ok and read_sidecar(file) then
		return false, "Another session advertised this file; use :PeerpadJoin"
	end
	assert(ok, "Cannot create " .. file .. ": " .. tostring(err))
	owner.sidecar = file
	return true
end

local function unpublish(owner)
	local info = owner.sidecar and read_sidecar(owner.sidecar)
	if info and info.token == owner.token then
		vim.uv.fs_unlink(owner.sidecar)
	end
end

local function send_next(session)
	if not session.connected or session.sent then
		return
	end
	if session.queue[1] then
		session.sent = true
		session.connection:send({ type = "edit", revision = session.revision, operation = session.queue[1] })
		return
	end
	-- Cursors are sent only when synchronized, so the offset is in server coordinates.
	local win = vim.api.nvim_get_current_win()
	if session.cursor_moved and vim.api.nvim_win_get_buf(win) == session.buf then
		session.cursor_moved = false
		local cursor = vim.api.nvim_win_get_cursor(win)
		local offset = vim.api.nvim_buf_get_offset(session.buf, cursor[1] - 1) + cursor[2]
		if offset ~= session.reported_cursor then
			session.reported_cursor = offset
			session.connection:send({ type = "cursor", revision = session.revision, offset = offset })
		end
	end
end

local function schedule_send(session)
	if not session.connected then
		return
	end
	if not session.send_scheduled then
		session.send_scheduled = true
		vim.schedule(function()
			session.send_scheduled = false
			send_next(session)
		end)
	end
end

-- Draw a peer's cursor; extmarks then follow later edits on their own.
local function show_peer(session, id, label, offset)
	for _, pending in ipairs(session.queue) do
		offset = op.move(offset, pending)
	end
	local row, col = op.position(session.text, math.min(offset, #session.text - 1))
	local line = vim.api.nvim_buf_get_lines(session.buf, row, row + 1, true)[1]
	local peer = session.peers[id] or {}
	session.peers[id], peer.label = peer, label
	local hl = "LiveSharePeer" .. ((id - 1) % 6 + 1)
	peer.mark = vim.api.nvim_buf_set_extmark(session.buf, cursor_ns, row, col, {
		id = peer.mark,
		end_col = col < #line and col + 1 + vim.str_utf_end(line, col + 1) or nil,
		hl_group = hl,
		virt_text = { { " " .. label .. " ", hl } },
		virt_text_pos = "eol",
	})
end

-- Each inverse is based on the state after undoing all newer entries.
local function trim_history(history)
	while #history > 1000 or (history.bytes or 0) > 4 * limit do
		history.bytes = history.bytes - op.size(table.remove(history, 1))
	end
end

local function rebase_history(history, remote)
	for i = #history, 1, -1 do
		local previous_size = op.size(history[i])
		remote, history[i] = op.transform(remote, history[i])
		history.bytes = (history.bytes or 0) + op.size(history[i]) - previous_size
	end
	trim_history(history)
end

local function push_history(history, operation)
	history[#history + 1] = operation
	history.bytes = (history.bytes or 0) + op.size(operation)
	trim_history(history)
end

local function patch_buffer(session, operation)
	local before, after = session.text, op.apply(session.text, operation)
	document_valid(after)
	if before == after then
		return
	end
	local first, removed, inserted = op.difference(before:sub(1, -2), after:sub(1, -2))
	local positions = {}
	for _, win in ipairs(vim.fn.win_findbuf(session.buf)) do
		local cursor = vim.api.nvim_win_get_cursor(win)
		local offset = vim.api.nvim_buf_get_offset(session.buf, cursor[1] - 1) + cursor[2]
		positions[win] = op.move(offset, operation)
	end
	session.applying = true
	local row, col = op.position(before, first)
	local end_row, end_col = op.position(before, first + removed)
	local ok, err = pcall(
		vim.api.nvim_buf_set_text,
		session.buf,
		row,
		col,
		end_row,
		end_col,
		vim.split(inserted, "\n", { plain = true })
	)
	session.applying = false
	assert(ok, err)
	session.text = after
	for win, offset in pairs(positions) do
		local new_row, new_col = op.position(after, math.min(offset, #after - 1))
		vim.api.nvim_win_set_cursor(win, { new_row + 1, new_col })
	end
end

local function record(session, operation, kind)
	local inverse = op.inverse(session.text, operation)
	if kind == "undo" then
		push_history(session.redo, inverse)
	elseif kind == "redo" then
		push_history(session.undo, inverse)
	else
		push_history(session.undo, inverse)
		session.redo = {}
	end
	-- Bound disconnected edits as well as network traffic.
	if session.connected then
		session.queue[#session.queue + 1] = operation
		session.queue_bytes = session.queue_bytes + op.size(operation)
		if #session.queue > 1000 or session.queue_bytes > 4 * limit then
			vim.schedule(function()
				session.connection:stop("Too many unacknowledged edits; local text was retained")
			end)
		end
	end
end

local function undo(session, redo)
	local history = redo and session.redo or session.undo
	for _ = 1, math.max(1, vim.v.count1) do
		local operation = table.remove(history)
		if not operation then
			break
		end
		history.bytes = history.bytes - op.size(operation)
		-- Check before queueing: a queued edit that is not applied locally diverges.
		local ok, after = pcall(op.apply, session.text, operation)
		if not ok or not pcall(document_valid, after) then
			notify("That change can no longer be undone", vim.log.levels.WARN)
			break
		end
		record(session, operation, redo and "redo" or "undo")
		patch_buffer(session, operation)
	end
	send_next(session)
end

local function write_shared(session)
	local owner = server
	if not owner or owner.session ~= session then
		notify("Only the session owner saves the source file", vim.log.levels.WARN)
		return
	end
	if not session.connected or #session.queue > 0 or session.text ~= owner.text then
		notify("Wait for pending edits to synchronize before saving", vim.log.levels.WARN)
		return
	end
	if
		not vim.api.nvim_buf_is_loaded(owner.source)
		or not policy.is_source(owner.source)
		or not vim.bo[owner.source].modifiable
		or vim.api.nvim_buf_get_changedtick(owner.source) ~= owner.source_tick
		or vim.api.nvim_buf_get_name(owner.source) ~= owner.path
		or disk_content(owner.path) ~= owner.disk
	then
		notify("Source file changed outside this session; save was refused", vim.log.levels.ERROR)
		return
	end
	vim.api.nvim_buf_set_lines(owner.source, 0, -1, false, vim.split(owner.text:sub(1, -2), "\n", { plain = true }))
	owner.source_tick = vim.api.nvim_buf_get_changedtick(owner.source)
	local ok, err = pcall(vim.api.nvim_buf_call, owner.source, function()
		vim.cmd("write")
	end)
	owner.source_tick = vim.api.nvim_buf_get_changedtick(owner.source)
	owner.disk = disk_content(owner.path)
	if not ok then
		notify(tostring(err), vim.log.levels.ERROR)
		return
	end
	-- Formatting/save hooks may have changed the source; never silently diverge.
	if table.concat(vim.api.nvim_buf_get_lines(owner.source, 0, -1, false), "\n") .. "\n" ~= owner.text then
		notify("A source write hook changed the file; stop sharing before continuing", vim.log.levels.ERROR)
		M.stop()
		return
	end
	vim.bo[session.buf].modified = false
	notify("Saved " .. owner.path)
end

local function create_buffer(session, message)
	local buf = vim.api.nvim_create_buf(true, false)
	session.buf, session.text, session.file = buf, message.text, message.file
	vim.api.nvim_buf_set_name(
		buf,
		"peerpad://" .. message.session .. "/" .. session.id .. "/" .. vim.fs.basename(message.file)
	)
	vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "acwrite", "hide", false
	vim.bo[buf].undofile, vim.bo[buf].undolevels = false, -1
	-- Text comes from peers; never let it set options.
	vim.bo[buf].modeline = false
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(message.text:sub(1, -2), "\n", { plain = true }))
	vim.bo[buf].filetype = message.filetype
	vim.bo[buf].modified = false
	vim.b[buf].live_shared = true
	local name = vim.api.nvim_buf_get_name(buf)
	vim.api.nvim_create_autocmd({ "BufWriteCmd", "FileWriteCmd", "FileAppendCmd" }, {
		group = group,
		buf = buf,
		callback = function(args)
			if not session.connected then
				notify("Disconnected snapshot: copy its text into a normal buffer to save", vim.log.levels.WARN)
			elseif args.event == "BufWriteCmd" and vim.api.nvim_buf_get_name(buf) == name then
				write_shared(session)
			else
				notify(
					"Shared buffers cannot write another path; copy text into a normal buffer first",
					vim.log.levels.WARN
				)
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		group = group,
		buf = buf,
		callback = function()
			session.cursor_moved = true
			schedule_send(session)
		end,
	})
	vim.keymap.set("n", "u", function()
		undo(session, false)
	end, { buf = buf, desc = "Undo my shared edit" })
	vim.keymap.set("n", "<C-r>", function()
		undo(session, true)
	end, { buf = buf, desc = "Redo my shared edit" })
	vim.api.nvim_buf_attach(buf, false, {
		on_bytes = function(_, _, _, row, col, start, _, _, removed, added_rows, added_col)
			if session.disabled then
				return true
			end
			if session.applying then
				return
			end
			local count = vim.api.nvim_buf_line_count(buf)
			local finish = row + added_rows
			local lines = vim.api.nvim_buf_get_lines(buf, row, math.min(finish + 1, count), true)
			if finish < count then
				lines[#lines] = lines[#lines]:sub(1, added_rows == 0 and col + added_col or added_col)
			else
				lines[#lines + 1] = ""
			end
			lines[1] = lines[1]:sub(col + 1)
			local inserted = table.concat(lines, "\n")
			local operation = op.splice(#session.text, start, removed, inserted)
			local ok, after = pcall(op.apply, session.text, operation)
			if ok then
				ok = pcall(document_valid, after)
			end
			-- splice may move an edit off the final newline; the text must not change.
			if ok and start + removed == #session.text then
				ok = after == session.text:sub(1, start) .. inserted
			end
			if not ok then
				session.disabled = true
				vim.schedule(function()
					if vim.api.nvim_buf_is_valid(buf) then
						-- A rejected edit is already in the buffer. Never apply old inverses
						-- to that new, unsynchronized text during recovery.
						vim.keymap.del("n", "u", { buf = buf })
						vim.keymap.del("n", "<C-r>", { buf = buf })
						vim.bo[buf].undolevels = vim.go.undolevels
					end
					local reason = "Unsupported edit; buffer retained, sharing stopped"
					if session.connection.closed then
						notify(reason, vim.log.levels.WARN)
					else
						session.connection:stop(reason)
					end
				end)
				return
			end
			if after == session.text then
				return
			end
			record(session, operation)
			session.text = after
			schedule_send(session)
		end,
		on_detach = function()
			vim.schedule(function()
				if client == session then
					M.stop()
				end
			end)
		end,
	})
	local target = session.target
	if
		vim.api.nvim_win_is_valid(target.win)
		and vim.api.nvim_win_get_buf(target.win) == target.buf
		and vim.api.nvim_buf_get_changedtick(target.buf) == target.tick
		and vim.api.nvim_buf_get_name(target.buf) == target.name
	then
		vim.api.nvim_win_set_buf(target.win, buf)
	else
		notify("Original window changed; shared buffer is available with :buffer " .. buf)
	end
end

-- Reclaim only redundant shared text. Never overwrite or reload a source buffer.
local function finish_buffer(session)
	local buf, source = session.buf, session.target.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return ""
	end
	vim.b[buf].live_shared = false
	vim.api.nvim_buf_clear_namespace(buf, cursor_ns, 0, -1)
	if
		vim.api.nvim_buf_is_loaded(source)
		and policy.is_source(source)
		and vim.api.nvim_buf_get_name(source) == session.file
		and #session.queue == 0
		and vim.deep_equal(
			vim.api.nvim_buf_get_lines(buf, 0, -1, false),
			vim.api.nvim_buf_get_lines(source, 0, -1, false)
		)
	then
		for _, win in ipairs(vim.fn.win_findbuf(buf)) do
			vim.api.nvim_win_call(win, function()
				local view = vim.fn.winsaveview()
				vim.api.nvim_win_set_buf(win, source)
				vim.fn.winrestview(view)
			end)
		end
		vim.api.nvim_buf_delete(buf, { force = true })
		return "; returned to source buffer"
	end
	local name = vim.api.nvim_buf_get_name(buf)
	vim.api.nvim_buf_set_name(buf, vim.fs.dirname(name) .. "/[disconnected] " .. vim.fs.basename(session.file))
	return "; disconnected snapshot retained"
end

-- Try each advertised host in order until one completes the handshake.
local function connect(hosts, port, token, owner)
	assert(not client, "Already sharing; use :PeerpadStop first")
	local focus_editor = policy.focus_editor
	if not owner and not policy.is_editor(0) and focus_editor then
		focus_editor()
	end
	local buf = vim.api.nvim_get_current_buf()
	local session = {
		queue = {},
		queue_bytes = 0,
		undo = {},
		redo = {},
		peers = {},
		connected = false,
		target = owner and owner.target or {
			win = vim.api.nvim_get_current_win(),
			buf = buf,
			tick = vim.api.nvim_buf_get_changedtick(buf),
			name = vim.api.nvim_buf_get_name(buf),
		},
	}
	client = session
	if owner then
		owner.session = session
	end
	local attempt
	local function receive(_, message)
		if message.type == "welcome" then
			assert(not session.connected, "Repeated welcome")
			document_valid(message.text)
			op.valid_text(message.text)
			session.connection:settle()
			session.id, session.revision, session.connected = message.id, message.revision, true
			create_buffer(session, message)
			for _, peer in ipairs(type(message.cursors) == "table" and message.cursors or {}) do
				show_peer(session, peer.id, printable(peer.label, 128), peer.offset)
			end
			session.cursor_moved = true
			send_next(session)
			notify("Connected. u/Ctrl+r undo only your edits; :PeerpadStop disconnects")
		elseif message.type == "edit" then
			assert(session.connected and message.revision == session.revision + 1, "Revision mismatch")
			if session.reported_cursor then
				session.reported_cursor = op.move(session.reported_cursor, message.operation)
			end
			if message.id == session.id then
				assert(session.sent and session.queue[1], "Unexpected acknowledgement")
				session.queue_bytes = session.queue_bytes - op.size(table.remove(session.queue, 1))
				session.sent = false
			else
				local remote = message.operation
				for i, pending in ipairs(session.queue) do
					remote, session.queue[i] = op.transform(remote, pending)
					session.queue_bytes = session.queue_bytes + op.size(session.queue[i]) - op.size(pending)
				end
				patch_buffer(session, remote)
				rebase_history(session.undo, remote)
				rebase_history(session.redo, remote)
			end
			session.revision = message.revision
			send_next(session)
		elseif message.type == "cursor" then
			assert(session.connected and message.revision == session.revision, "Revision mismatch")
			assert(type(message.id) == "number" and type(message.offset) == "number", "Invalid cursor")
			show_peer(session, message.id, printable(message.label, 128), message.offset)
		elseif message.type == "refused" then
			-- Every advertised address reaches the same server; do not retry.
			session.refused = true
			error(printable(message.reason, 128), 0)
		elseif message.type == "leave" then
			local peer = session.peers[message.id]
			if peer and peer.mark and vim.api.nvim_buf_is_valid(session.buf) then
				vim.api.nvim_buf_del_extmark(session.buf, cursor_ns, peer.mark)
			end
			session.peers[message.id] = nil
		else
			error("Unknown server message")
		end
	end
	local function disconnected(reason)
		if not session.id and not session.refused and client == session and hosts[session.attempt + 1] then
			attempt(session.attempt + 1)
			return
		end
		session.connected = false
		if client == session then
			client = nil
		end
		local outcome = finish_buffer(session)
		if not session.silent then
			notify((reason or "Disconnected") .. outcome, reason and vim.log.levels.WARN or vim.log.levels.INFO)
		end
	end
	function attempt(index)
		local host, socket = hosts[index], vim.uv.new_tcp()
		local connection = channel(socket, receive, disconnected)
		session.attempt, session.connection = index, connection
		-- Unreachable advertised interfaces otherwise block for the OS TCP timeout.
		connection:deadline(5000, "Cannot reach " .. host .. ":" .. port)
		vim.uv.getaddrinfo(
			host,
			nil,
			{ socktype = "stream" },
			vim.schedule_wrap(function(err, addresses)
				if connection.closed then
					return
				end
				if err or not addresses or not addresses[1] then
					connection:stop(err or "Cannot resolve " .. host)
					return
				end
				socket:connect(
					addresses[1].addr,
					port,
					vim.schedule_wrap(function(connect_error)
						if connection.closed then
							return
						end
						if connect_error then
							connection:stop(connect_error)
							return
						end
						connection:read()
						connection:send({
							type = "hello",
							token = token,
							protocol = 2,
							user = vim.uv.os_get_passwd().username,
						})
					end)
				)
			end)
		)
	end
	attempt(1)
end

function M.start(args)
	assert(not server and not client, "Already sharing; use :PeerpadStop first")
	local source = vim.api.nvim_get_current_buf()
	assert(policy.allows(source) and vim.bo[source].modifiable, "Share a normal, editable source buffer")
	assert(vim.o.encoding == "utf-8", "UTF-8 is required")
	local path = vim.api.nvim_buf_get_name(source)
	assert(path ~= "", "Save/name the source file before sharing")
	local text = table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), "\n") .. "\n"
	document_valid(text)
	op.valid_text(text)
	local port = args[1] and tonumber(args[1]) or 0
	assert(port and port >= 0 and port <= 65535 and port == math.floor(port), "Invalid port")
	assert(#args <= 2, "Usage: Peerpad [port] [bind-address]")
	local owner = {
		text = text,
		revision = 0,
		history = {},
		history_floor = 0,
		history_bytes = 0,
		peers = {},
		next_id = 0,
		token = vim.fn.sha256(vim.uv.random(32)),
		target = {
			win = vim.api.nvim_get_current_win(),
			buf = source,
			tick = vim.api.nvim_buf_get_changedtick(source),
			name = path,
		},
		source = source,
		source_tick = vim.api.nvim_buf_get_changedtick(source),
		path = path,
		filetype = vim.bo[source].filetype,
		disk = disk_content(path),
	}
	-- Participants including the owner; unauthenticated connections count until they time out.
	owner.capacity = math.max(2, math.min(require("peerpad").config.max_peers, 64))
	-- Loopback peers (the owner, same-host guests) are labelled with this host's address.
	local hosts = advertised(args[2] or "0.0.0.0")
	owner.ip = hosts[2] or hosts[1]
	assert(owner.disk ~= false, "Source file on disk exceeds 2 MiB")
	local listener = vim.uv.new_tcp()
	owner.listener = listener
	local address = args[2] or "0.0.0.0"
	local ok, err = listener:bind(address, port)
	if not ok then
		close(listener)
		error(err)
	end
	server = owner
	ok, err = listener:listen(
		8,
		vim.schedule_wrap(function(accept_error)
			if server ~= owner or accept_error then
				return
			end
			local socket = vim.uv.new_tcp()
			listener:accept(socket)
			local full = vim.tbl_count(owner.peers) >= owner.capacity
			local peer
			peer = channel(socket, function(connection, message)
				if not connection.id then
					assert(
						message.type == "hello" and message.protocol == 2 and message.token == owner.token,
						"Authentication failed or incompatible peerpad protocol"
					)
					connection:settle()
					owner.next_id = owner.next_id + 1
					connection.id = owner.next_id
					-- The address is what the server observed, not what the peer claims.
					local ip = (socket:getpeername() or {}).ip or "?"
					if ip:find("^127%.") or ip == "::1" or ip:find("^::ffff:127%.") then
						ip = owner.ip
					end
					local label = printable(message.user or "?") .. "@" .. ip
					-- Same user on one host (or the owner's host) needs a distinguishing suffix.
					for _, member in pairs(owner.peers) do
						if member.label == label then
							label = label .. " #" .. connection.id
							break
						end
					end
					connection.label = label
					local cursors = {}
					for _, member in pairs(owner.peers) do
						if member.cursor then
							cursors[#cursors + 1] = { id = member.id, label = member.label, offset = member.cursor }
						end
					end
					connection:send({
						type = "welcome",
						id = connection.id,
						revision = owner.revision,
						text = owner.text,
						file = owner.path,
						filetype = owner.filetype,
						session = owner.token:sub(1, 16),
						cursors = cursors,
					})
					return
				end
				if message.type == "cursor" then
					local revision, offset = message.revision, message.offset
					assert(
						type(revision) == "number"
							and revision == math.floor(revision)
							and type(offset) == "number"
							and offset == math.floor(offset)
							and offset >= 0,
						"Invalid cursor"
					)
					if revision < owner.history_floor or revision > owner.revision then
						return
					end
					local length = revision == owner.revision and #owner.text or owner.history[revision + 1].length
					assert(offset <= length, "Invalid cursor")
					for i = revision + 1, owner.revision do
						offset = op.move(offset, owner.history[i].operation)
					end
					connection.cursor = offset
					for _, member in pairs(owner.peers) do
						if member.id and member ~= connection then
							member:send({
								type = "cursor",
								id = connection.id,
								label = connection.label,
								revision = owner.revision,
								offset = offset,
							})
						end
					end
					return
				end
				assert(message.type == "edit", "Unknown client message")
				local revision = message.revision
				assert(type(revision) == "number" and revision == math.floor(revision), "Invalid revision")
				assert(
					revision >= owner.history_floor and revision <= owner.revision,
					"Client is too far behind; reconnect"
				)
				local operation = message.operation
				-- Validate against its original base before transforming untrusted operations.
				local length = revision == owner.revision and #owner.text or owner.history[revision + 1].length
				op.validate(operation, length)
				for i = revision + 1, owner.revision do
					local _, rebased = op.transform(owner.history[i].operation, operation)
					operation = rebased
				end
				local after = op.apply(owner.text, operation)
				document_valid(after)
				owner.revision = owner.revision + 1
				owner.history[owner.revision] = { operation = operation, length = #owner.text }
				owner.history_bytes = owner.history_bytes + op.size(operation)
				while owner.revision - owner.history_floor > 1024 or owner.history_bytes > 4 * limit do
					owner.history_floor = owner.history_floor + 1
					owner.history_bytes = owner.history_bytes - op.size(owner.history[owner.history_floor].operation)
					owner.history[owner.history_floor] = nil
				end
				owner.text = after
				for _, member in pairs(owner.peers) do
					if member.cursor then
						member.cursor = op.move(member.cursor, operation)
					end
					if member.id then
						member:send({
							type = "edit",
							id = connection.id,
							revision = owner.revision,
							operation = operation,
						})
					end
				end
			end, function()
				owner.peers[peer] = nil
				if peer.id then
					for _, member in pairs(owner.peers) do
						if member.id then
							member:send({ type = "leave", id = peer.id })
						end
					end
				end
			end)
			if full then
				-- Tell the joiner why instead of resetting the connection.
				peer:send({ type = "refused", reason = "Session is full (" .. owner.capacity .. " participants)" })
				socket:shutdown(vim.schedule_wrap(function()
					peer:stop()
				end))
				return
			end
			owner.peers[peer] = peer
			peer:deadline(10000, "Authentication timed out")
			peer:read()
		end)
	)
	if not ok then
		M.stop()
		error(err)
	end
	owner.port = listener:getsockname().port
	local published, reason
	ok, published, reason = pcall(publish, owner, address)
	if ok and published == false then
		M.stop()
		error(reason, 0)
	elseif not ok then
		notify(
			"Automatic discovery unavailable: " .. tostring(published) .. "; manual joining still works",
			vim.log.levels.WARN
		)
	end
	connect(
		{ address == "0.0.0.0" and "127.0.0.1" or address == "::" and "::1" or address },
		owner.port,
		owner.token,
		owner
	)
	notify(
		"Port "
			.. owner.port
			.. (owner.sidecar and ". Others opening this file are offered to join. Manual: " or ". Manual: ")
			.. ":PeerpadJoin <host> "
			.. owner.port
			.. " "
			.. owner.token
	)
end

-- Join the session advertised beside a source file. `ask` prompts first.
function M.discover(buf, ask)
	if ask and (vim.api.nvim_get_current_buf() ~= buf or not policy.is_editor(0)) then
		return
	end
	local path = vim.api.nvim_buf_get_name(buf)
	local file = sidecar_path(path)
	local info = read_sidecar(file)
	if not info then
		if ask then
			return
		end
		error("No live share for this file; use :PeerpadJoin <host> <port> <token>", 0)
	end
	if server and server.token == info.token then
		return
	end
	local who = info.user .. "@" .. info.host
	if stale(info) then
		if info.uid == vim.uv.getuid() then
			vim.uv.fs_unlink(file)
		end
		notify("Ignored a stale share from " .. who .. " (its Neovim exited)", vim.log.levels.WARN)
		return
	end
	if client then
		notify(who .. " is sharing this file; :PeerpadStop, then :PeerpadJoin", vim.log.levels.WARN)
		return
	end
	local question = who .. " is live-sharing " .. vim.fs.basename(path) .. ". Join?"
	if ask and vim.fn.confirm(question, "&Join\n&Not now", 2) ~= 1 then
		return
	end
	local hosts = {}
	if info.host == vim.uv.os_gethostname() then
		hosts[1] = "127.0.0.1"
		vim.list_extend(hosts, info.hosts)
	else
		-- Skip this machine's addresses: identical bridge IPs (e.g. docker0) or loopback
		-- would reach a local service instead of the owner.
		local own = { localhost = true }
		for _, addresses in pairs(vim.uv.interface_addresses()) do
			for _, address in ipairs(addresses) do
				own[address.ip] = true
			end
		end
		for _, host in ipairs(info.hosts) do
			if not own[host] and not host:find("^127%.") then
				hosts[#hosts + 1] = host
			end
		end
	end
	assert(hosts[1], who .. " advertises no reachable address")
	connect(hosts, info.port, info.token)
end

function M.join(args)
	if #args == 0 then
		M.discover(vim.api.nvim_get_current_buf(), false)
		return
	end
	assert(#args == 3, "Usage: PeerpadJoin [<host> <port> <token>]")
	local port = tonumber(args[2])
	assert(port and port > 0 and port <= 65535 and port == math.floor(port), "Invalid port")
	connect({ args[1] }, port, args[3])
end

local function stop(silent)
	local owner, session = server, client
	server, client = nil, nil
	if session then
		session.silent = silent
		session.connection:stop()
	end
	if owner then
		unpublish(owner)
		close(owner.listener)
		for _, peer in pairs(owner.peers) do
			peer:stop()
		end
	end
	-- Shared scratch text stays available; never overwrite or destroy a source buffer.
	if owner and owner.session and owner.session ~= session then
		owner.session.silent = silent
		owner.session.connection:stop()
	end
	if owner and not session and not silent then
		notify("Sharing stopped")
	end
end

function M.stop()
	stop(false)
end

function M.status()
	if not client then
		notify(server and "Server running; local client disconnected" or "Not sharing")
		return
	end
	local lines = {
		(server and "Owner" or "Guest")
			.. ", revision "
			.. (client.revision or 0)
			.. ", pending edits "
			.. #client.queue,
	}
	for _, peer in pairs(client.peers) do
		local row, col = unpack(vim.api.nvim_buf_get_extmark_by_id(client.buf, cursor_ns, peer.mark, {}))
		lines[#lines + 1] = ("  %s at line %d, column %d"):format(peer.label, row + 1, col + 1)
	end
	notify(table.concat(lines, "\n"))
end

vim.api.nvim_create_autocmd("VimLeavePre", {
	group = group,
	callback = function()
		stop(true)
	end,
})
return M
