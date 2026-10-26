local policy = require("buffer_policy")
local shared = require("state")

-- =========================================
-- ============ SEARCH: FILES ============
-- =========================================
-- <leader>f: project files; <leader>sn: configuration files; <leader>sr: recent files.
-- Collect files asynchronously; use the installed fzf binary, or built-in matchfuzzy when absent.
function shared.file_items(files, root)
	local items = {}
	for _, file in ipairs(files) do
		if file ~= "" then
			local label = root and file:sub(1, #root + 1) == root .. "/" and file:sub(#root + 2)
				or vim.fn.fnamemodify(file, ":~:.")
			items[#items + 1] = { filename = file, lnum = 1, label = label }
		end
	end
	return items
end
local function cancel_search()
	shared.cancel_command("search")
end
local function file_picker(title, root, cancel)
	local executable = vim.fn.exepath("fzf")
	if executable ~= "" then
		return require("fzf_picker").open(title, root, executable, cancel)
	end
	return shared.open_picker(title, { cancel = cancel })
end
-- Check old files off the UI thread, with bounded filesystem concurrency.
function shared.recent_files(picker)
	local paths, files = vim.v.oldfiles, {}
	local index, completed = 0, 0
	local function check_next()
		if picker.closed or index == #paths then
			return
		end
		index = index + 1
		local position, path = index, paths[index]
		local function finish(ok)
			files[position] = ok and path or false
			completed = completed + 1
			if picker.closed then
				return
			end
			if completed == #paths then
				vim.schedule(function()
					if not picker.closed then
						local readable = vim.iter(files)
							:filter(function(file)
								return file
							end)
							:totable()
						picker.set_files(readable)
					end
				end)
			else
				check_next()
			end
		end
		vim.uv.fs_stat(path, function(_, stat)
			if picker.closed then
				return
			end
			if not stat or stat.type ~= "file" then
				finish(false)
				return
			end
			vim.uv.fs_access(path, "R", function(_, ok)
				finish(ok)
			end)
		end)
	end
	if #paths == 0 then
		picker.set_files({})
	end
	for _ = 1, math.min(8, #paths) do
		check_next()
	end
end
function shared.file_picker(title, root, command)
	local picker = file_picker(title, root, cancel_search)
	shared.run_command("search", command, {
		cwd = root,
		partial = true,
		failed = function()
			picker.set_files({})
		end,
	}, function(output, limited)
		local files = shared.records(output, "\0", limited)
		for i, file in ipairs(files) do
			if file:sub(1, 1) ~= "/" then
				files[i] = root .. "/" .. file
			end
		end
		picker.set_files(files, root)
	end)
	return picker
end

function shared.find_files(root, title)
	local command = { "find", root, "-type", "d", "(" }
	for i, name in ipairs({
		".git",
		"node_modules",
		"__pycache__",
		".venv",
		"venv",
		"build",
		"build-*",
		"cmake-build-*",
		"dist",
	}) do
		if i > 1 then
			command[#command + 1] = "-o"
		end
		vim.list_extend(command, { "-name", name })
	end
	vim.list_extend(command, { ")", "-prune", "-o", "-type", "f", "-print0" })
	shared.file_picker(title, root, command)
end
shared.map("n", "<leader>f", function()
	shared.find_files(shared.project_root(), "Find files")
end, "Find files: fuzzy picker")
shared.map("n", "<leader>sn", function()
	shared.find_files(vim.fn.stdpath("config"), "Neovim files")
end, "Find config files")
shared.map("n", "<leader>sr", function()
	shared.recent_files(file_picker("Recent files", vim.fn.getcwd()))
end, "Recent files")
-- =========================================
-- ======= SEARCH: EDITOR METADATA =======
-- =========================================
-- <leader>sc/sh/sk/sp: commands, help, keymaps and themes. Cancelling a theme preview restores the original theme.
local function command_picker(title, kind, action)
	local items = {}
	for _, name in ipairs(vim.fn.getcompletion("", kind)) do
		items[#items + 1] = {
			label = name,
			action = function()
				action(name)
			end,
		}
	end
	shared.open_picker(title, { items = items })
end
shared.map("n", "<leader>sc", function()
	command_picker("Commands", "command", function(name)
		vim.api.nvim_feedkeys(":" .. name .. " ", "n", true)
	end)
end, "Search commands")
shared.map("n", "<leader>sh", function()
	command_picker("Help", "help", function(name)
		vim.cmd("help " .. vim.fn.fnameescape(name))
	end)
end, "Search help")
shared.map("n", "<leader>sp", function()
	local original = vim.g.colors_name or "default"
	local background = vim.o.background
	local function apply(name)
		-- A preview may change 'background'; each candidate starts from the same preference.
		vim.o.background = background
		vim.cmd("colorscheme " .. name)
	end
	local items = {}
	for _, name in ipairs(vim.fn.getcompletion("", "color")) do
		items[#items + 1] = {
			label = name,
			action = function()
				apply(name)
			end,
		}
	end
	shared.open_picker("Colorschemes", {
		items = items,
		highlight = function(item)
			if item then
				apply(item.label)
			end
		end,
		on_cancel = function()
			apply(original)
			vim.o.background = background
		end,
	})
end, "Preview and choose colorscheme")
shared.map("n", "<leader>sk", function()
	local items = {}
	local leader = vim.keycode("<leader>")
	for _, mode in ipairs({ "n", "i", "x", "t" }) do
		for _, source in ipairs({
			{ scope = "[global]", mappings = vim.api.nvim_get_keymap(mode) },
			{ scope = "[buffer]", mappings = vim.api.nvim_buf_get_keymap(0, mode) },
		}) do
			for _, key in ipairs(source.mappings) do
				local lhs = key.lhsraw or vim.keycode(key.lhs)
				local label = lhs:sub(1, #leader) == leader and ("<leader>" .. vim.fn.keytrans(lhs:sub(#leader + 1)))
					or vim.fn.keytrans(lhs)
				items[#items + 1] = {
					label = mode
						.. " "
						.. source.scope
						.. " "
						.. label
						.. "  "
						.. (key.desc or key.rhs or "Lua callback"),
				}
			end
		end
	end
	shared.open_picker("Keymaps", { items = items })
end, "Search keymaps")
-- =========================================
-- ======= SEARCH: TEXT / LIVE GREP ======
-- =========================================
-- <leader>st: regex search on each input change; <leader>t: literal word/selection search, then filter results.
-- <leader>s/: search the on-disk contents of open files. Prefer rg, falling back to grep.
-- New input cancels the previous job to prevent stale search results from appearing later.
local function search(text, paths, root, fixed, callback)
	if not text or text == "" then
		return
	end
	local use_rg = vim.fn.executable("rg") == 1
	local multiline = text:find("\n", 1, true) ~= nil
	if multiline and not use_rg then
		vim.notify("Multiline selection search requires ripgrep (rg)", vim.log.levels.WARN)
		callback({})
		return
	end
	local argv
	if use_rg then
		argv = {
			"rg",
			"--vimgrep",
			"--hidden",
			"--smart-case",
			"--max-columns",
			"300",
			"--max-columns-preview",
			"--max-filesize",
			"2M",
			"--glob",
			"!.git/**",
			"--glob",
			"!node_modules/**",
			"--glob",
			"!__pycache__/**",
			"--",
			text,
		}
	else
		argv = {
			"grep",
			"-r",
			"-n",
			"-H",
			"-I",
			fixed and "-F" or "-E",
			"--exclude-dir=.git",
			"--exclude-dir=node_modules",
			"--exclude-dir=__pycache__",
		}
		if not text:find("%u") then
			argv[#argv + 1] = "-i"
		end
		vim.list_extend(argv, { "-e", text, "--" })
	end
	if use_rg and fixed then
		table.insert(argv, 2, "--fixed-strings")
	end
	if multiline then
		table.insert(argv, 2, "--multiline")
	end
	vim.list_extend(argv, paths)
	shared.run_command("search", argv, {
		cwd = root,
		partial = true,
		no_match = true,
		failed = function()
			callback({})
		end,
	}, function(output, limited)
		local items = {}
		for _, line in ipairs(shared.records(output, "\n", limited, 10000)) do
			local filename, lnum, col, content
			if use_rg then
				filename, lnum, col, content = line:match("^(.-):(%d+):(%d+):(.*)$")
			else
				filename, lnum, content = line:match("^(.-):(%d+):(.*)$")
				col = "1"
			end
			if filename and #items < 10000 then
				items[#items + 1] = {
					filename = filename,
					lnum = tonumber(lnum),
					col = tonumber(col),
					text = content:sub(1, 300),
					label = filename:sub(1, #root + 1) == root .. "/"
							and (filename:sub(#root + 2) .. ":" .. lnum .. " " .. content:sub(1, 200))
						or line:sub(1, 300),
				}
			end
		end
		callback(items)
	end)
end

local function text_picker(open_only, word)
	local root = shared.project_root()
	local paths = { root }
	if open_only then
		paths = {}
		for _, buf in ipairs(shared.buffers()) do
			local name = vim.api.nvim_buf_get_name(buf)
			if policy.is_source(buf) and name ~= "" then
				paths[#paths + 1] = name
			end
		end
	end
	local function update(text, picker, generation)
		cancel_search()
		if text == "" or #paths == 0 then
			if not picker.closed and (not generation or generation == picker.generation) then
				picker.set_items({})
			end
			return
		end
		search(text, paths, root, word ~= nil, function(items)
			if not picker.closed and (not generation or generation == picker.generation) then
				picker.set_items(items)
			end
		end)
	end
	local picker = shared.open_picker(
		word and ("Word: " .. word:gsub("%c", " ")) or (open_only and "Grep open files" or "Live grep"),
		{
			cancel = cancel_search,
			live = not word and update or nil,
		}
	)
	if word then
		update(word, picker)
	end
end
shared.map("n", "<leader>st", function()
	text_picker(false)
end, "Live grep: update while typing")
shared.map("n", "<leader>t", function()
	text_picker(false, vim.fn.expand("<cword>"))
end, "Find cursor word, then refine matches")
shared.map("x", "<leader>t", function()
	local text = table.concat(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() }), "\n")
	if text == "" then
		return
	end
	vim.cmd.normal({ vim.keycode("<Esc>"), bang = true })
	text_picker(false, text)
end, "Find selection, then refine matches")
shared.map("n", "<leader>s/", function()
	text_picker(true)
end, "Live grep in open files")
