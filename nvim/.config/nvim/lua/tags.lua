local policy = require("buffer_policy")
local backend = require("analysis_backend")
local shared = require("state")

-- =========================================
-- ====== CTAGS: INDEX / NAVIGATION ======
-- =========================================
-- Universal / Exuberant Ctags only. No automatic installation.
-- gd builds the project once; InsertEnter and outline index only the current file.
-- Saves replace that file's tags after 750ms; failed jobs preserve the old cache.
shared.tag_projects = {}
shared.definition_requests = {}
function shared.finish_tag_waiters(waiters, succeeded, output, cancelled)
	for _, waiter in ipairs(waiters) do
		local callback = waiter.failed
		if succeeded then
			callback = waiter.after
		end
		if callback then
			local ok, err = pcall(callback, output, cancelled)
			if not ok then
				vim.notify(tostring(err), vim.log.levels.WARN)
			end
		end
	end
end
function shared.cancel_tag_build(root, project)
	project.generation = project.generation + 1
	shared.cancel_command("ctags:" .. root)
	local waiters = project.waiters
	if project.active then
		vim.list_extend(waiters, project.active.waiters)
		for file in pairs(project.active.files) do
			project.pending[file] = true
		end
	end
	project.active, project.save_version = nil, nil
	project.waiters, project.full, project.quiet = {}, false, true
	shared.finish_tag_waiters(waiters, false, nil, true)
end
local ctags_checked, ctags_kind, ctags_command
local tag_work_sequence = 0
local function ctags_candidates()
	local candidates, seen = {}, {}
	local function add(path)
		if path and path ~= "" and not seen[path] then
			seen[path] = true
			candidates[#candidates + 1] = path
		end
	end
	add(vim.g.nopack_ctags)
	local executable = vim.fn.has("win32") == 1 and "ctags.exe" or "ctags"
	local separator = vim.fn.has("win32") == 1 and ";" or ":"
	for _, directory in ipairs(vim.split(vim.env.PATH or "", separator, { plain = true, trimempty = true })) do
		add(vim.fs.joinpath(directory, executable))
	end
	return candidates
end
local ctags_probe
local cancel_generation = 0
vim.api.nvim_create_autocmd("User", {
	pattern = "NopackCancel",
	callback = function()
		cancel_generation = cancel_generation + 1
		if ctags_probe then
			ctags_probe, ctags_checked = nil, nil
		end
		for root, project in pairs(shared.tag_projects) do
			shared.cancel_tag_build(root, project)
		end
		for _, request in pairs(shared.definition_requests) do
			request.cancel()
		end
	end,
})
local function ctags_available(quiet, callback)
	local candidates = ctags_candidates()
	local checked = table.concat(candidates, "\0")
	local function answer(available)
		if not available and not quiet then
			vim.notify(
				"Universal or Exuberant Ctags required; check ctags --version or g:nopack_ctags",
				vim.log.levels.WARN
			)
		end
		callback(available)
	end
	if ctags_probe and not shared.running["ctags-probe"] then
		ctags_probe, ctags_checked = nil, nil
	end
	if ctags_probe and ctags_probe.key == checked then
		ctags_probe.waiters[#ctags_probe.waiters + 1] = answer
		return
	end
	if ctags_checked == checked and not ctags_probe then
		answer(ctags_kind ~= nil)
		return
	end
	local probe = { key = checked, waiters = { answer } }
	ctags_probe = probe
	ctags_checked, ctags_kind, ctags_command = checked, nil, nil
	shared.ctags_kind = nil
	local index, fallback = 0, nil
	local function finish()
		if ctags_probe ~= probe then
			return
		end
		ctags_probe = nil
		if not ctags_kind and fallback then
			ctags_kind, ctags_command = "exuberant", fallback
		end
		shared.ctags_kind = ctags_kind == "universal" and "Universal"
			or ctags_kind == "exuberant" and "Exuberant"
			or nil
		vim.cmd("redrawstatus")
		for _, waiter in ipairs(probe.waiters) do
			waiter(ctags_kind ~= nil)
		end
	end
	local next_candidate
	next_candidate = function()
		if ctags_probe ~= probe then
			return
		end
		index = index + 1
		while candidates[index] and vim.fn.executable(candidates[index]) == 0 do
			index = index + 1
		end
		local command = candidates[index]
		if not command then
			finish()
			return
		end
		shared.run_command("ctags-probe", { command, "--options=NONE", "--version" }, {
			quiet = true,
			timeout = 2000,
			max_bytes = 65536,
			failed = next_candidate,
		}, function(version)
			if ctags_probe ~= probe then
				return
			end
			if version:find("Universal Ctags", 1, true) then
				ctags_kind, ctags_command = "universal", command
				finish()
			else
				if version:find("Exuberant Ctags", 1, true) then
					fallback = fallback or command
				end
				next_candidate()
			end
		end)
	end
	next_candidate()
end
function shared.tag_context(buf)
	if not vim.api.nvim_buf_is_valid(buf) or not policy.allows(buf) then
		return
	end
	local file = vim.api.nvim_buf_get_name(buf)
	if file == "" then
		return
	end
	file = vim.uv.fs_realpath(file) or file
	local root = shared.find_project(vim.fs.dirname(file))
	return root, file
end
local function tag_project(root)
	if not shared.tag_projects[root] then
		vim.fn.mkdir(shared.nopack_data .. "/tags", "p")
		shared.tag_projects[root] = {
			path = shared.nopack_data .. "/tags/" .. vim.fn.sha256(root),
			pending = {},
			waiters = {},
			quiet = true,
			generation = 0,
		}
	end
	return shared.tag_projects[root]
end
local managed_tags = {}
local function attach_tags(buf)
	local tags, previous = vim.bo[buf].tags, managed_tags[buf]
	if not previous and not next(shared.tag_projects) then
		return
	end
	if previous and tags:sub(1, #previous) == previous then
		tags = tags:sub(#previous + 1)
	end
	local root = shared.tag_context(buf)
	local project = root and shared.tag_projects[root]
	local prefix = project and (vim.fn.escape(project.path, " ,\\") .. ",") or nil
	tags = (prefix or "") .. tags
	if vim.bo[buf].tags ~= tags then
		vim.bo[buf].tags = tags
	end
	managed_tags[buf] = prefix
end
local function tag_command()
	local command = { ctags_command, "--options=NONE" }
	vim.list_extend(
		command,
		ctags_kind == "exuberant" and { "--format=2", "--extra=-q", "--tag-relative=no" }
			or { "--output-format=e-ctags", "--extras=-q", "--tag-relative=never" }
	)
	return vim.list_extend(command, {
		"--fields=+nK",
		"--sort=yes",
		"--links=no",
		"--langmap=C++:+.ipp.cu.cuh,Python:+.pyi",
		"-f",
		"-",
	})
end
function shared.tag_filename(line)
	local file = line:match("^[^\t]+\t([^\t]+)") or ""
	return (file:gsub("\\(.)", { t = "\t", r = "\r", n = "\n", ["\\"] = "\\" }))
end
local function run_tag_build(root, full, changed, after, failed, quiet)
	local project = tag_project(root)
	project.generation = project.generation + 1
	local generation = project.generation
	shared.cancel_command("ctags:" .. root)
	ctags_available(quiet, function(available)
		if shared.tag_projects[root] ~= project or project.generation ~= generation then
			return
		end
		if not available then
			if failed then
				failed()
			end
			return
		end
		local function save(output)
			-- Pure Lua/file IO runs in libuv's worker pool; only publication touches the editor.
			tag_work_sequence = tag_work_sequence + 1
			local temporary = project.path .. "." .. vim.fn.getpid() .. "." .. tag_work_sequence .. ".tmp"
			local work
			work = vim.uv.new_work(
				function(content, path, target, replaced_files, replace_all)
					local ok, err = pcall(function()
						local lines, replaced = {}, {}
						for file in replaced_files:gmatch("[^%z]+") do
							replaced[file] = true
						end
						for line in content:gmatch("[^\n]+") do
							if not line:match("^!_TAG_") then
								lines[#lines + 1] = line
							end
						end
						if not replace_all then
							local input = io.open(path, "r")
							if input then
								for line in input:lines() do
									local file = line:match("^[^\t]+\t([^\t]+)") or ""
									file = file:gsub("\\(.)", { t = "\t", r = "\r", n = "\n", ["\\"] = "\\" })
									if not line:match("^!_TAG_") and not replaced[file] then
										lines[#lines + 1] = line
									end
								end
								input:close()
							end
							table.sort(lines)
						end
						local output_file = assert(io.open(target, "w"))
						local wrote, write_err = pcall(function()
							assert(output_file:write("!_TAG_FILE_SORTED\t1\t/0=unsorted, 1=sorted/\n"))
							for _, line in ipairs(lines) do
								assert(output_file:write(line, "\n"))
							end
						end)
						local closed, close_err = output_file:close()
						assert(wrote, write_err)
						assert(closed, close_err)
					end)
					return ok, ok and "" or tostring(err)
				end,
				vim.schedule_wrap(function(ok, err)
					work = nil
					if shared.tag_projects[root] ~= project or project.generation ~= generation then
						vim.fn.delete(temporary)
						return
					end
					if ok then
						ok, err = vim.uv.fs_rename(temporary, project.path)
					end
					vim.fn.delete(temporary)
					if not ok then
						vim.notify(tostring(err), vim.log.levels.WARN)
						if failed then
							failed()
						end
						return
					end
					if full then
						project.ready = true
					end
					for _, buf in ipairs(vim.api.nvim_list_bufs()) do
						attach_tags(buf)
					end
					if after then
						after(output)
					end
				end)
			)
			work:queue(output, project.path, temporary, table.concat(changed, "\0"), full)
		end
		local function run(command, stdin)
			shared.run_command("ctags:" .. root, command, {
				cwd = root,
				stdin = stdin,
				timeout = full and 120000 or 10000,
				max_bytes = (full and 64 or 16) * 1024 * 1024,
				failed = failed,
			}, save)
		end
		if not full then
			-- Use stdin rather than argv so a burst of saves cannot exceed ARG_MAX.
			table.sort(changed)
			run(vim.list_extend(tag_command(), { "-L", "-" }), table.concat(changed, "\n") .. "\n")
		elseif vim.uv.fs_stat(root .. "/.git") then
			shared.run_command(
				"ctags:" .. root,
				{ "git", "ls-files", "-z", "--cached", "--others", "--exclude-standard" },
				{
					cwd = root,
					timeout = 30000,
					max_bytes = 16 * 1024 * 1024,
					failed = failed,
				},
				function(output)
					local sources, seen = {}, {}
					for _, file in ipairs(shared.records(output, "\0")) do
						local path = root .. "/" .. file
						if not file:find("[\r\n]") and not seen[path] and vim.fn.filereadable(path) == 1 then
							sources[#sources + 1], seen[path] = path, true
						end
					end
					if #sources == 0 then
						save("")
					else
						run(vim.list_extend(tag_command(), { "-L", "-" }), table.concat(sources, "\n") .. "\n")
					end
				end
			)
		else
			local command = tag_command()
			for _, dir in ipairs({
				".git",
				".venv",
				"venv",
				"node_modules",
				"__pycache__",
				"build",
				"build-*",
				"cmake-build-*",
				"dist",
			}) do
				command[#command + 1] = "--exclude=" .. dir
			end
			run(vim.list_extend(command, { "-R", root }))
		end
	end)
end
function shared.build_tags(root, full, files, after, failed, quiet)
	local project = tag_project(root)
	for _, file in ipairs(files or {}) do
		project.pending[file] = true
	end
	project.full = project.full or full
	project.quiet = project.quiet and quiet == true
	if after or failed then
		project.waiters[#project.waiters + 1] = { after = after, failed = failed }
	end
	if project.active or (not project.full and not next(project.pending)) then
		return
	end
	-- Snapshot this batch so saves and requests arriving during it remain queued.
	local batch = { files = project.pending, full = project.full, waiters = project.waiters, quiet = project.quiet }
	project.pending, project.waiters, project.full, project.quiet = {}, {}, false, true
	project.active = batch
	local function finish(succeeded, output)
		if shared.tag_projects[root] ~= project or project.active ~= batch then
			return
		end
		project.active = nil
		local queued = project.full or next(project.pending)
		if not succeeded then
			for file in pairs(batch.files) do
				project.pending[file] = true
			end
		end
		local generation = project.generation
		shared.finish_tag_waiters(batch.waiters, succeeded, output)
		if queued and shared.tag_projects[root] == project and project.generation == generation then
			shared.build_tags(root, false, nil, nil, nil, true)
		end
	end
	run_tag_build(root, batch.full, vim.tbl_keys(batch.files), function(output)
		finish(true, output)
	end, function()
		finish(false)
	end, batch.quiet)
end
local function request_tags(full, after, quiet)
	shared.focus_editor()
	local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
	local root, file = shared.tag_context(buf)
	if not root or file:find("[\r\n]") then
		return
	end
	local context, position = policy.source_context(buf), vim.api.nvim_win_get_cursor(win)
	shared.build_tags(root, full, { file }, after and function()
		if
			policy.allows(buf)
			and vim.api.nvim_win_is_valid(win)
			and vim.api.nvim_get_current_win() == win
			and vim.api.nvim_win_get_buf(win) == buf
			and policy.source_unchanged(context)
			and vim.deep_equal(vim.api.nvim_win_get_cursor(win), position)
		then
			vim.api.nvim_win_call(win, after)
		else
			vim.notify("Ctags index ready; repeat navigation in the desired file")
		end
	end, nil, quiet)
end
local function ctags_definition()
	shared.focus_editor()
	local root = shared.tag_context(vim.api.nvim_get_current_buf())
	local word = vim.fn.expand("<cword>")
	if not root or word == "" then
		return
	end
	if vim.bo.modified then
		vim.notify("Ctags uses saved files; save edits to update definitions")
	end
	local function jump()
		attach_tags(vim.api.nvim_get_current_buf())
		local tags = vim.fn.taglist("\\C^\\V" .. vim.fn.escape(word, "\\") .. "\\m$", vim.fn.expand("%:p"))
		if #tags == 0 then
			vim.notify("No definition in saved project files: " .. word)
		else
			vim.cmd("tjump " .. vim.fn.fnameescape(word))
		end
	end
	if tag_project(root).ready then
		jump()
	else
		request_tags(true, jump)
	end
end
shared.map("n", "g<C-t>", "<Cmd>pop<CR>", "Return from ctags definition")
vim.api.nvim_create_user_command("CtagsUpdate", function()
	request_tags(true)
end, {})
vim.api.nvim_create_user_command("CtagsClearAll", function()
	for root, project in pairs(shared.tag_projects) do
		shared.cancel_tag_build(root, project)
	end
	shared.tag_projects = {}
	vim.fn.delete(shared.nopack_data .. "/tags", "rf")
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		vim.b[buf].nopack_tags_requested = nil
		attach_tags(buf)
	end
	vim.notify("Cleared all managed ctags caches")
end, {})
vim.api.nvim_create_autocmd({ "BufEnter", "BufFilePost", "FileType" }, {
	callback = function(args)
		if args.event ~= "BufEnter" then
			vim.b[args.buf].nopack_tags_requested = nil
		end
		attach_tags(args.buf)
		if policy.allows(args.buf) and vim.bo[args.buf].filetype ~= "" and backend.get(args.buf) == "ctags" then
			ctags_available(true, function() end)
		end
	end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
	callback = function(args)
		managed_tags[args.buf] = nil
	end,
})
local function ensure_tag_completion(buf)
	if
		vim.b[buf].nopack_tags_requested
		or not policy.allows(buf)
		or vim.bo[buf].filetype == ""
		or backend.get(buf) ~= "ctags"
	then
		return
	end
	local root, file = shared.tag_context(buf)
	if not root or file:find("[\r\n]") then
		return
	end
	vim.b[buf].nopack_tags_requested = true
	shared.build_tags(root, false, { file }, nil, function()
		if vim.api.nvim_buf_is_valid(buf) then
			vim.b[buf].nopack_tags_requested = nil
		end
	end, true)
end
vim.api.nvim_create_autocmd("InsertEnter", {
	callback = function(args)
		local generation = cancel_generation
		vim.schedule(function()
			if generation == cancel_generation and vim.api.nvim_buf_is_valid(args.buf) then
				ensure_tag_completion(args.buf)
			end
		end)
	end,
})
vim.api.nvim_create_autocmd("BufWritePost", {
	callback = function(args)
		if not policy.allows(args.buf) or backend.get(args.buf) ~= "ctags" then
			return
		end
		local root, file = shared.tag_context(args.buf)
		local project = root and shared.tag_projects[root]
		if not project or file:find("[\r\n]") then
			return
		end
		project.pending[file] = true
		local version = {}
		project.save_version = version
		vim.defer_fn(function()
			if shared.tag_projects[root] == project and project.save_version == version then
				shared.build_tags(root, false, nil, nil, nil, true)
			end
		end, 750)
	end,
})

local function definition_target_name(item)
	local location = item.location
	local uri = location.uri or location.targetUri
	local range = location.targetSelectionRange or location.range
	if not uri or not range then
		return
	end
	local filename = vim.uri_to_fname(uri)
	local row = range.start.line
	local line
	local target_buf = vim.fn.bufnr(filename)
	if target_buf > 0 and vim.api.nvim_buf_is_loaded(target_buf) then
		line = vim.api.nvim_buf_get_lines(target_buf, row, row + 1, false)[1]
	elseif vim.fn.filereadable(filename) == 1 then
		line = vim.fn.readfile(filename, "", row + 1)[row + 1]
	end
	if not line then
		return
	end
	local ok_start, start_byte = pcall(vim.str_byteindex, line, item.encoding, range.start.character, false)
	local ok_end, end_byte = pcall(vim.str_byteindex, line, item.encoding, range["end"].character, false)
	if not ok_start or not ok_end then
		return
	end
	local name = line:sub(start_byte + 1, end_byte)
	return name:match("^[_%a][_%w]*$") and name or nil
end

-- Select LSP or ctags for the language; request failures must not switch backends.
shared.map("n", "gd", function()
	shared.focus_editor()
	local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
	if not policy.allows(buf) then
		return
	end
	local source_word = vim.fn.expand("<cword>")
	local position, context = vim.api.nvim_win_get_cursor(win), policy.source_context(buf)
	local previous = shared.definition_requests[buf]
	if previous then
		-- Repeated gd at the unchanged position shares the outstanding request.
		if
			previous.win == win
			and vim.deep_equal(previous.position, position)
			and policy.source_unchanged(previous.context)
		then
			return
		end
		previous.cancel()
	end
	if backend.get(buf) == "ctags" then
		ctags_definition()
		return
	end
	local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/definition" })
	if #clients == 0 then
		vim.notify("LSP definition provider is not connected or does not support definitions", vim.log.levels.WARN)
		return
	end
	local request = { win = win, position = position, context = context, clients = {} }
	for _, client in ipairs(clients) do
		request.clients[client.id] = true
	end
	local done, cancel = false, nil
	local function stop(completed)
		if done then
			return
		end
		done = true
		shared.definition_requests[buf] = nil
		if not completed and cancel then
			cancel()
		end
	end
	request.cancel = stop
	shared.definition_requests[buf] = request
	local function is_current()
		return policy.allows(buf)
			and vim.api.nvim_win_is_valid(win)
			and vim.api.nvim_get_current_win() == win
			and vim.api.nvim_win_get_buf(win) == buf
			and policy.source_unchanged(context)
			and vim.deep_equal(vim.api.nvim_win_get_cursor(win), position)
	end
	local send
	local function finish(results)
		if done then
			return
		end
		-- A late response must not redirect another window, file, or a moved cursor.
		if not is_current() then
			stop(true)
			return
		end
		local locations, errors, content_modified = {}, {}, false
		for id, response in pairs(results) do
			local client = vim.lsp.get_client_by_id(id)
			local result = response.result
			if response.err then
				content_modified = content_modified or response.err.code == vim.lsp.protocol.ErrorCodes.ContentModified
				errors[#errors + 1] = (client and client.name or tostring(id)) .. ": " .. response.err.message
			elseif client and result and result ~= vim.NIL then
				for _, location in ipairs(vim.islist(result) and result or { result }) do
					locations[#locations + 1] = { location = location, encoding = client.offset_encoding }
				end
			end
		end
		-- A server-side project change invalidates the request, not the definition.
		-- Recreate it once at the unchanged position; do not restart or poll the server.
		if #locations == 0 and content_modified and not request.retried then
			request.retried = true
			vim.schedule(send)
			return
		end
		stop(true)
		if #locations == 0 and #errors > 0 then
			vim.notify("LSP definition failed: " .. table.concat(errors, "; "), vim.log.levels.WARN)
			return
		end
		if #locations > 1 and source_word ~= "" then
			local exact = {}
			for _, item in ipairs(locations) do
				if definition_target_name(item) == source_word then
					exact[#exact + 1] = item
				end
			end
			if #exact > 0 then
				locations = exact
			end
		end
		if #locations == 0 then
			vim.notify("No LSP definition found: " .. source_word)
		elseif #locations == 1 then
			vim.lsp.util.show_document(locations[1].location, locations[1].encoding, { focus = true })
		else
			local items = {}
			for _, item in ipairs(locations) do
				local choice = vim.lsp.util.locations_to_items({ item.location }, item.encoding)[1]
				choice.label = choice.filename .. ":" .. choice.lnum
				choice.action = function()
					vim.lsp.util.show_document(item.location, item.encoding, { focus = true })
				end
				items[#items + 1] = choice
			end
			shared.open_picker("Definitions:", { items = items })
		end
	end
	send = function()
		if done then
			return
		end
		if not is_current() then
			stop(true)
			return
		end
		cancel = vim.lsp.buf_request_all(buf, "textDocument/definition", function(client)
			return vim.lsp.util.make_position_params(win, client.offset_encoding)
		end, finish)
	end
	send()
end, "Go to definition: LSP or ctags")

-- Connection lifetime, rather than a deadline, determines pending request validity.
vim.api.nvim_create_autocmd("LspDetach", {
	callback = function(args)
		local request = shared.definition_requests[args.buf]
		if request and request.clients[args.data.client_id] then
			request.cancel()
		end
	end,
})

vim.api.nvim_create_autocmd({ "BufUnload", "BufFilePost", "FileType" }, {
	callback = function(args)
		if shared.definition_requests[args.buf] then
			shared.definition_requests[args.buf].cancel()
		end
	end,
})

vim.api.nvim_create_autocmd("User", {
	pattern = "NopackBufferRestricted",
	callback = function(args)
		local buf = args.data.buf
		attach_tags(buf)
		if shared.definition_requests[buf] then
			shared.definition_requests[buf].cancel()
		end
		local file = vim.api.nvim_buf_get_name(buf)
		file = vim.uv.fs_realpath(file) or file
		local root = file ~= "" and shared.find_project(vim.fs.dirname(file))
		local project = root and shared.tag_projects[root]
		if project and (project.pending[file] or (project.active and project.active.files[file])) then
			shared.cancel_tag_build(root, project)
			project.pending[file] = nil
			if next(project.pending) then
				shared.build_tags(root, false)
			end
		end
	end,
})
