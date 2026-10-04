local policy = require("buffer_policy")
local shared = require("state")

-- =========================================
-- ============ SEARCH: FILES ============
-- =========================================
-- <leader>f: 프로젝트 파일, <leader>sn: 설정 파일, <leader>sr: 최근 파일.
-- find 결과를 비동기로 수집한 뒤 내장 matchfuzzy로 좁힙니다. Git 파일 키는 GIT에 있습니다.
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
function shared.file_picker(title, root, command)
	local picker = shared.open_picker(title, { cancel = cancel_search })
	shared.run_command("search", command, {
		cwd = root,
		partial = true,
		failed = function()
			picker.set_items({})
		end,
	}, function(output, limited)
		local files = shared.records(output, "\0", limited)
		for i, file in ipairs(files) do
			if file:sub(1, 1) ~= "/" then
				files[i] = root .. "/" .. file
			end
		end
		picker.set_items(shared.file_items(files, root))
	end)
	return picker
end

function shared.find_files(root, title)
	shared.file_picker(title, root, {
		"find",
		root,
		"-type",
		"d",
		"(",
		"-name",
		".git",
		"-o",
		"-name",
		"node_modules",
		"-o",
		"-name",
		"__pycache__",
		"-o",
		"-name",
		".venv",
		"-o",
		"-name",
		"venv",
		"-o",
		"-name",
		"build",
		"-o",
		"-name",
		"build-*",
		"-o",
		"-name",
		"cmake-build-*",
		"-o",
		"-name",
		"dist",
		")",
		"-prune",
		"-o",
		"-type",
		"f",
		"-print0",
	})
end
shared.map("n", "<leader>f", function()
	shared.find_files(shared.project_root(), "Find files")
end, "Find files: fuzzy picker")
shared.map("n", "<leader>sn", function()
	shared.find_files(vim.fn.stdpath("config"), "Neovim files")
end, "Find config files")
shared.map("n", "<leader>sr", function()
	local files = vim.tbl_filter(function(file)
		return file ~= "" and vim.fn.filereadable(file) == 1
	end, vim.v.oldfiles)
	shared.open_picker("Recent files", { items = shared.file_items(files) })
end, "Recent files")
-- =========================================
-- ======= SEARCH: EDITOR METADATA =======
-- =========================================
-- <leader>sc/sh/sk/sp: 명령·도움말·키맵·테마. 테마 미리보기 취소 시 원래 테마를 복구합니다.
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
	for _, mode in ipairs({ "n", "i", "x", "t" }) do
		for _, source in ipairs({
			{ scope = "[global]", mappings = vim.api.nvim_get_keymap(mode) },
			{ scope = "[buffer]", mappings = vim.api.nvim_buf_get_keymap(0, mode) },
		}) do
			for _, key in ipairs(source.mappings) do
				items[#items + 1] = {
					label = mode
						.. " "
						.. source.scope
						.. " "
						.. key.lhs
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
-- <leader>st: 입력마다 정규식 검색; <leader>t: 커서 단어를 고정 검색 후 결과 필터.
-- <leader>s/: 열린 파일의 디스크 내용만 검색. rg 우선, 없으면 grep 사용.
-- 새 입력은 이전 작업을 취소하여 오래된 검색 결과가 뒤늦게 표시되지 않게 합니다.
local function search(text, paths, root, fixed, callback)
	if not text or text == "" then
		return
	end
	local use_rg = vim.fn.executable("rg") == 1
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
	local picker = shared.open_picker(word and ("Word: " .. word) or (open_only and "Grep open files" or "Live grep"), {
		cancel = cancel_search,
		live = not word and update or nil,
	})
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
shared.map("n", "<leader>s/", function()
	text_picker(true)
end, "Live grep in open files")
