local explorer = require("explorer")
local policy = require("buffer_policy")
local shared = require("state")
local actions = require("git_actions")

-- =========================================
-- ====== GIT: FILES / STATUS / DIFF =====
-- =========================================
-- 설치된 git으로 현재 프로젝트를 조회합니다. 네트워크 명령은 실행하지 않습니다.
-- <leader><CR>: 추적 파일 picker; sg/gg: 로그/상태; gd/gD: index/HEAD 좌우 diff.
-- <leader>gn/gp: diff 이동; gb: 현재 줄 inline blame 토글.
-- 상태줄: 브랜치와 현재 파일의 index/worktree 상태(XY). 미저장 편집은 기존 %m으로 표시.
-- 화면을 그릴 때는 버퍼 캐시만 읽고, 파일 진입·저장·터미널 복귀 시 비동기로 갱신합니다.
-- Explorer Git signs: XY is index/worktree status; ** aggregates mixed children.
local netrw_git_namespace = vim.api.nvim_create_namespace("nopack-netrw-git")
local netrw_git_timer = -1
local netrw_git_updated = -1000
local netrw_git_cache = {}
local netrw_git_drawn = {}
local netrw_git_snapshots = {}

function shared.netrw_git_top(win, buf)
	return explorer.root(buf)
end

local function netrw_git_statuses(root, output)
	local statuses = {}
	local entries = vim.split(output, "\0", { plain = true, trimempty = true })
	local index = 1
	while index <= #entries do
		local record = entries[index]
		local xy = record:sub(1, 2)
		local path = (root:gsub("/+$", "") .. "/" .. record:sub(4)):gsub("/+$", "")
		index = index + (xy:find("[RC]") and 2 or 1)
		while path ~= root and path ~= vim.fs.dirname(path) do
			statuses[path] = statuses[path] and statuses[path] ~= xy and "**" or xy
			path = vim.fs.dirname(path)
		end
	end
	return statuses
end

local function draw_netrw_git(win, buf, top, statuses)
	if
		not vim.api.nvim_win_is_valid(win)
		or vim.api.nvim_win_get_buf(win) ~= buf
		or not explorer.is_buffer(buf)
		or shared.netrw_git_top(win, buf) ~= top
	then
		return
	end
	netrw_git_cache[top] = statuses
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	local drawn = netrw_git_drawn[buf]
	if drawn and drawn.top == top and drawn.tick == tick and drawn.statuses == statuses then
		return
	end
	netrw_git_drawn[buf] = { top = top, tick = tick, statuses = statuses }
	local existing = {}
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, netrw_git_namespace, 0, -1, { details = true })) do
		existing[mark[1]] = mark
	end
	for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		local path = explorer.path(buf, line, row)
		if path then
			local xy = statuses[path]
			if xy then
				local highlight = (xy:find("U") or xy == "AA" or xy == "DD") and "ErrorMsg"
					or xy == "**" and "Directory"
					or xy:find("D") and "DiffDelete"
					or xy:find("[A?]") and "DiffAdd"
					or "DiffChange"
				local text = xy:gsub(" ", ".")
				local previous = existing[row]
				existing[row] = nil
				if not previous or previous[2] ~= row - 1 or previous[4].sign_text ~= text then
					vim.api.nvim_buf_set_extmark(buf, netrw_git_namespace, row - 1, 0, {
						id = row,
						sign_text = text,
						sign_hl_group = highlight,
						priority = 20,
					})
				end
			end
		end
	end
	for id in pairs(existing) do
		vim.api.nvim_buf_del_extmark(buf, netrw_git_namespace, id)
	end
end

local function redraw_netrw_git()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if explorer.is_buffer(buf) then
			local top = shared.netrw_git_top(win, buf)
			draw_netrw_git(win, buf, top, netrw_git_cache[top] or {})
		end
	end
end

local function refresh_netrw_git()
	netrw_git_timer = -1
	netrw_git_updated = vim.uv.now()
	local projects = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if explorer.is_buffer(buf) then
			local top = shared.netrw_git_top(win, buf)
			local root = shared.find_git_root(top)
			if not root or vim.fn.isdirectory(top) == 0 then
				draw_netrw_git(win, buf, top, {})
			else
				projects[root] = true
			end
		end
	end
	for root in pairs(projects) do
		local key = "git-tree:" .. root
		-- One job and one status snapshot for every visible tree in this project.
		if shared.running[key] then
			if netrw_git_timer == -1 then
				netrw_git_timer = vim.fn.timer_start(1000, refresh_netrw_git)
			end
		else
			local function draw_project(statuses)
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					local buf = vim.api.nvim_win_get_buf(win)
					if explorer.is_buffer(buf) then
						local top = shared.netrw_git_top(win, buf)
						if shared.find_git_root(top) == root then
							draw_netrw_git(win, buf, top, statuses)
						end
					end
				end
			end
			shared.run_command(key, {
				"git",
				"--no-optional-locks",
				"status",
				"--porcelain=v1",
				"-z",
				"--untracked-files=all",
			}, {
				cwd = root,
				quiet = true,
				failed = function()
					netrw_git_snapshots[root] = nil
					draw_project({})
				end,
			}, function(output)
				local snapshot = netrw_git_snapshots[root]
				if not snapshot or snapshot.output ~= output then
					snapshot = { output = output, statuses = netrw_git_statuses(root, output) }
					netrw_git_snapshots[root] = snapshot
				end
				draw_project(snapshot.statuses)
			end)
		end
	end
end

local function queue_netrw_git()
	if netrw_git_timer ~= -1 then
		return
	end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if explorer.is_buffer(vim.api.nvim_win_get_buf(win)) then
			local delay = math.max(100, 1000 - (vim.uv.now() - netrw_git_updated))
			netrw_git_timer = vim.fn.timer_start(delay, refresh_netrw_git)
			return
		end
	end
end

local netrw_git_group = vim.api.nvim_create_augroup("nopack-netrw-git", { clear = true })
vim.api.nvim_create_autocmd("BufWipeout", {
	group = netrw_git_group,
	callback = function(args)
		netrw_git_drawn[args.buf] = nil
	end,
})
vim.api.nvim_create_autocmd("FileType", {
	group = netrw_git_group,
	pattern = "flash-explorer",
	callback = queue_netrw_git,
})
vim.api.nvim_create_autocmd(
	{ "BufWinEnter", "BufWritePost", "FocusGained", "ShellCmdPost", "TermLeave", "TermClose" },
	{
		group = netrw_git_group,
		callback = queue_netrw_git,
	}
)
vim.api.nvim_create_autocmd("TextChanged", {
	group = netrw_git_group,
	callback = function()
		if explorer.is_buffer(vim.api.nvim_get_current_buf()) then
			redraw_netrw_git()
		end
	end,
})
vim.api.nvim_create_autocmd("User", {
	group = netrw_git_group,
	pattern = "NopackExplorerChanged",
	callback = redraw_netrw_git,
})

local git_status_cache = {}
local function refresh_git_status(buf, force)
	if not vim.api.nvim_buf_is_loaded(buf) then
		return
	end
	local key = "git-status:" .. buf
	local file = vim.api.nvim_buf_get_name(buf)
	local root = policy.is_source(buf) and file ~= "" and shared.find_git_root(vim.fs.dirname(file))
	local snapshot = git_status_cache[buf]
	if not force and snapshot and snapshot.file == file and snapshot.root == root then
		return
	end
	local cache = git_status_cache
	local task = shared.running[key]
	-- Navigation can join an identical pending read; writes/external changes must replace it.
	if not force and task and task.file == file and task.root == root then
		return
	end
	shared.cancel_command(key)
	if not root or vim.fn.executable("git") == 0 then
		vim.b[buf].nopack_git_status = nil
		return
	end
	shared.run_command(key, {
		"git",
		"--no-optional-locks",
		"--literal-pathspecs",
		"status",
		"--porcelain=v2",
		"--branch",
		"--no-ahead-behind",
		"-z",
		"--",
		file,
	}, { cwd = root, quiet = true }, function(output)
		if not vim.api.nvim_buf_is_loaded(buf) or vim.api.nvim_buf_get_name(buf) ~= file then
			return
		end
		local branch, oid, xy
		for record in output:gmatch("[^%z]+") do
			branch = record:match("^# branch.head (.+)$") or branch
			oid = record:match("^# branch.oid (.+)$") or oid
			xy = record:match("^[12u] (%S+) ") or (record:sub(1, 2) == "? " and "??") or xy
		end
		if branch == "(detached)" then
			branch = "HEAD@" .. (oid or ""):sub(1, 7)
		end
		local status = branch and ("[" .. branch .. (xy and " " .. xy or "") .. "]") or ""
		if git_status_cache == cache then
			cache[buf] = { file = file, root = root }
		end
		if vim.b[buf].nopack_git_status ~= status then
			vim.b[buf].nopack_git_status = status
			vim.cmd("redrawstatus")
		end
	end)
	if shared.running[key] then
		shared.running[key].file, shared.running[key].root = file, root
	end
end
vim.api.nvim_create_autocmd({
	"BufEnter",
	"BufReadPost",
	"BufWritePost",
	"FileChangedShellPost",
	"FocusGained",
	"ShellCmdPost",
	"TermLeave",
	"TermClose",
}, {
	group = vim.api.nvim_create_augroup("nopack-git-status", { clear = true }),
	callback = function(args)
		-- Reading or saving one source must not invalidate unrelated snapshots.
		-- Utility writes (the editable tree) can affect several source files.
		if
			args.event == "BufReadPost"
			or args.event == "FileChangedShellPost"
			or (args.event == "BufWritePost" and policy.is_source(args.buf))
		then
			git_status_cache[args.buf] = nil
		elseif args.event ~= "BufEnter" then
			git_status_cache = {}
		end
		if args.event == "TermLeave" or args.event == "TermClose" then
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.fn.bufwinid(buf) ~= -1 then
					refresh_git_status(buf, true)
				end
			end
		else
			refresh_git_status(args.buf, args.event ~= "BufEnter")
		end
	end,
})
vim.api.nvim_create_autocmd("User", {
	group = "nopack-git-status",
	pattern = "NopackRefresh",
	callback = function()
		git_status_cache = {}
		refresh_git_status(vim.api.nvim_get_current_buf(), true)
	end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
	group = "nopack-git-status",
	callback = function(args)
		git_status_cache[args.buf] = nil
		shared.cancel_command("git-status:" .. args.buf)
	end,
})
local function git(args, callback, opts)
	local root, is_git = shared.project_root()
	if not is_git then
		vim.notify("Current file is not in a Git project")
		return
	end
	opts = opts or {}
	opts.cwd = root
	shared.run_command(opts.key or "git", vim.list_extend({ "git", "--no-pager" }, args), opts, callback)
end
local function show_output(lines, filetype, vertical)
	vim.cmd(vertical and "rightbelow vnew" or "botright new")
	vim.bo.buftype = "nofile"
	vim.bo.buflisted = false
	vim.bo.bufhidden = "wipe"
	vim.bo.swapfile = false
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.bo.filetype = filetype
	vim.bo.modifiable = false
end
local active_git_diff
local function open_git_diff(source_buf, source_win, base_lines, filetype)
	if active_git_diff then
		active_git_diff.close()
	end
	if not vim.api.nvim_win_is_valid(source_win) or vim.api.nvim_win_get_buf(source_win) ~= source_buf then
		return
	end
	local state = { closed = false }
	active_git_diff = state
	vim.api.nvim_set_current_win(source_win)
	vim.cmd("diffthis")
	show_output(base_lines, filetype, true)
	local base_buf, base_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
	vim.cmd("diffthis")
	local group = vim.api.nvim_create_augroup("nopack-git-diff-window", { clear = true })
	function state.close()
		if state.closed then
			return
		end
		state.closed, active_git_diff = true, nil
		pcall(vim.api.nvim_del_augroup_by_id, group)
		if vim.api.nvim_win_is_valid(source_win) then
			vim.api.nvim_win_call(source_win, function()
				vim.cmd("diffoff")
			end)
			if vim.api.nvim_win_is_valid(base_win) then
				vim.api.nvim_win_close(base_win, true)
			end
			vim.api.nvim_set_current_win(source_win)
		elseif vim.api.nvim_win_is_valid(base_win) and vim.api.nvim_buf_is_valid(source_buf) then
			vim.api.nvim_win_call(base_win, function()
				vim.cmd("diffoff")
			end)
			vim.api.nvim_win_set_buf(base_win, source_buf)
			vim.api.nvim_set_current_win(base_win)
		end
	end
	vim.keymap.set("n", "q", state.close, { buf = base_buf, nowait = true, desc = "Close Git diff" })
	vim.keymap.set("n", "<Esc>", state.close, { buf = base_buf, nowait = true, desc = "Close Git diff" })
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		pattern = { tostring(source_win), tostring(base_win) },
		callback = function()
			vim.schedule(state.close)
		end,
	})
end
shared.map("n", "<leader><CR>", function()
	local root, is_git = shared.project_root()
	if not is_git then
		vim.notify("Current file is not in a Git project")
		return
	end
	shared.file_picker("Git files", root, { "git", "ls-files", "-z" })
end, "Git files: fuzzy picker")
shared.map("n", "<leader>sg", function()
	git({ "log", "-50", "--oneline" }, function(output)
		show_output(shared.records(output, "\n"), "git")
	end)
end, "Git commits")
shared.map("n", "<leader>gg", function()
	if vim.fn.executable("lazygit") == 1 then
		local root = shared.project_root()
		local width = math.max(1, math.floor(vim.o.columns * 0.9))
		local height = math.max(1, math.floor(vim.o.lines * 0.9))
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].bufhidden = "wipe"
		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = width,
			height = height,
			row = math.floor((vim.o.lines - height) / 2),
			col = math.floor((vim.o.columns - width) / 2),
			style = "minimal",
			border = "none",
		})
		vim.wo[win][0].winhighlight = "Normal:Normal,NormalNC:Normal"
		local function close()
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
				vim.api.nvim_win_close(win, true)
			end
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
			shared.check_external_files()
		end
		local job = vim.fn.jobstart({ "lazygit" }, {
			term = true,
			cwd = root,
			on_exit = function()
				vim.schedule(close)
			end,
		})
		if job > 0 then
			vim.cmd("startinsert")
		else
			close()
			vim.notify("Could not start lazygit", vim.log.levels.ERROR)
		end
		return
	end
	git({ "status", "--short", "--branch", "--untracked-files=normal" }, function(output)
		show_output(shared.records(output, "\n"), "git")
	end)
end, "Lazygit / Git status")
for key, revision in pairs({ gd = ":", gD = "HEAD:" }) do
	shared.map("n", "<leader>" .. key, function()
		local file, buf, win =
			vim.api.nvim_buf_get_name(0), vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
		if not policy.allows(buf) or file == "" then
			vim.notify("Open a tracked file first")
			return
		end
		local root = shared.project_root()
		local relative = file:sub(#root + 2)
		local context = policy.source_context(buf)
		git({ "show", revision .. relative }, function(output)
			if policy.allows(buf) and policy.source_unchanged(context) then
				open_git_diff(buf, win, shared.records(output, "\n"), context.filetype)
			end
		end)
	end, "Diff against " .. revision .. " (:q to close)")
end
-- =========================================
-- ======== GIT: LINE CHANGE SIGNS =======
-- =========================================
-- 현재 버퍼(미저장 내용 포함)를 index와 비교하여 + / ~ / - 표시.
-- 버퍼별 단일 200ms 타이머. diff/행 정렬은 worker에서 실행하고 최신 결과만 표시합니다.
-- 미추적·바이너리·256 KiB 초과 파일은 제외합니다. 창 이동만으로 index를 다시 읽지 않습니다.
shared.git_signs = vim.api.nvim_create_namespace("nopack-git-signs")
local git_sign_timers
local git_sign_changes = {}
shared.git_sign_versions, git_sign_timers, shared.git_diff_jobs, shared.git_sign_rendered = {}, {}, {}, {}
local git_base_cache = {}
-- Git atomically replaces the index. Include inode and nanosecond timestamps so
-- same-size updates invalidate cached blobs, including in worktrees/submodules.
local function git_index_stamp(root)
	local function absolute(path)
		return (path:match("^[/\\]") or path:match("^%a:[/\\]")) and path or (root .. "/" .. path)
	end
	local index = vim.env.GIT_INDEX_FILE
	if not index then
		local gitdir = root .. "/.git"
		local info = vim.uv.fs_stat(gitdir)
		if info and info.type == "file" then
			local ok, lines = pcall(vim.fn.readfile, gitdir, "", 1)
			local target = ok and (lines[1] or ""):match("^gitdir: (.+)$")
			if not target then
				return nil
			end
			gitdir = absolute(target)
		end
		index = gitdir .. "/index"
	else
		index = absolute(index)
	end
	local info = vim.uv.fs_stat(index)
	if not info then
		return index .. ":missing"
	end
	return table.concat({
		index,
		info.dev,
		info.ino,
		info.size,
		info.mtime.sec,
		info.mtime.nsec,
		info.ctime.sec,
		info.ctime.nsec,
	}, ":")
end
local function git_hunk_rows(buf)
	local rows, previous = {}, nil
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, shared.git_signs, 0, -1, {})) do
		local row = mark[2]
		if previous == nil or row > previous + 1 then
			rows[#rows + 1] = row
		end
		previous = row
	end
	return rows
end

local function navigate_git_hunk(next_hunk)
	local rows = git_hunk_rows(vim.api.nvim_get_current_buf())
	if #rows == 0 then
		vim.notify("No Git changes in this buffer")
		return
	end
	local current = vim.api.nvim_win_get_cursor(0)[1] - 1
	local target = next_hunk and rows[1] or rows[#rows]
	if next_hunk then
		for _, row in ipairs(rows) do
			if row > current then
				target = row
				break
			end
		end
	else
		for index = #rows, 1, -1 do
			if rows[index] < current then
				target = rows[index]
				break
			end
		end
	end
	vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
	vim.cmd("normal! zv")
end

shared.map("n", "<leader>gn", function()
	navigate_git_hunk(true)
end, "Next Git hunk")
shared.map("n", "<leader>gp", function()
	navigate_git_hunk(false)
end, "Previous Git hunk")

local inline_blame = {
	enabled = false,
	namespace = vim.api.nvim_create_namespace("nopack-inline-blame"),
	timer = -1,
	version = 0,
}
local function clear_inline_blame(buf)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_clear_namespace(buf, inline_blame.namespace, 0, -1)
	end
end
local function stop_inline_blame()
	inline_blame.buf, inline_blame.line = nil, nil
	if inline_blame.timer ~= -1 then
		vim.fn.timer_stop(inline_blame.timer)
		inline_blame.timer = -1
	end
	shared.cancel_command("git-inline-blame")
end
local function refresh_inline_blame()
	inline_blame.timer = -1
	local buf = vim.api.nvim_get_current_buf()
	clear_inline_blame(buf)
	if not inline_blame.enabled or not policy.allows(buf) or vim.bo[buf].modified then
		return
	end
	local file = vim.api.nvim_buf_get_name(buf)
	local root = file ~= "" and shared.find_git_root(vim.fs.dirname(file))
	if not root or vim.fn.executable("git") == 0 then
		return
	end
	local line = vim.api.nvim_win_get_cursor(0)[1]
	inline_blame.version = inline_blame.version + 1
	local version = inline_blame.version
	shared.run_command("git-inline-blame", {
		"git",
		"--no-pager",
		"blame",
		"--porcelain",
		"-L",
		line .. "," .. line,
		"--",
		file,
	}, { cwd = root, quiet = true }, function(output)
		if
			not inline_blame.enabled
			or inline_blame.version ~= version
			or vim.api.nvim_get_current_buf() ~= buf
			or vim.bo[buf].modified
			or vim.api.nvim_win_get_cursor(0)[1] ~= line
		then
			return
		end
		local hash = output:match("^(%x+)") or ""
		local author = output:match("\nauthor ([^\n]+)") or "Unknown"
		local timestamp = tonumber(output:match("\nauthor%-time (%d+)"))
		local date = timestamp and os.date("%Y-%m-%d", timestamp) or ""
		local summary = output:match("\nsummary ([^\n]+)") or ""
		if hash:match("^0+$") then
			author, date, summary = "Not committed", "", ""
		end
		local parts = { author }
		if date ~= "" then
			parts[#parts + 1] = date
		end
		if summary ~= "" then
			parts[#parts + 1] = summary
		end
		vim.api.nvim_buf_set_extmark(buf, inline_blame.namespace, line - 1, 0, {
			virt_text = { { "  " .. table.concat(parts, " • "), "Comment" } },
			virt_text_pos = "eol",
			priority = 10,
		})
	end)
end
local function queue_inline_blame(delay)
	stop_inline_blame()
	if not inline_blame.enabled or not policy.allows(0) then
		return
	end
	inline_blame.buf = vim.api.nvim_get_current_buf()
	inline_blame.line = vim.api.nvim_win_get_cursor(0)[1]
	inline_blame.timer = vim.fn.timer_start(delay or 150, refresh_inline_blame)
end
shared.map("n", "<leader>gb", function()
	inline_blame.enabled = not inline_blame.enabled
	if inline_blame.enabled then
		queue_inline_blame(0)
	else
		stop_inline_blame()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			clear_inline_blame(buf)
		end
	end
	vim.notify("Inline blame: " .. (inline_blame.enabled and "on" or "off"))
end, "Toggle inline blame")
vim.api.nvim_create_autocmd({
	"CursorMoved",
	"BufEnter",
	"BufWritePost",
	"BufFilePost",
	"FocusGained",
	"ShellCmdPost",
	"TermLeave",
	"TermClose",
}, {
	group = vim.api.nvim_create_augroup("nopack-inline-blame", { clear = true }),
	callback = function(args)
		if
			args.event == "CursorMoved"
			and inline_blame.buf == args.buf
			and inline_blame.line == vim.api.nvim_win_get_cursor(0)[1]
		then
			return
		end
		queue_inline_blame()
	end,
})
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufLeave" }, {
	group = "nopack-inline-blame",
	callback = function(args)
		stop_inline_blame()
		clear_inline_blame(args.buf)
	end,
})

function shared.stop_git_sign_timer(buf)
	local timer = git_sign_timers[buf]
	git_sign_timers[buf] = nil
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
end

-- No editor API or main-thread upvalues in this function: luv serializes it.
local function compute_git_marks(base, current, count)
	local ok, result = pcall(function()
		local old = vim.split(base, "\n", { plain = true })
		local new = vim.split(current, "\n", { plain = true })
		if #old > 20001 then
			return {}
		end
		local hunks = vim.text.diff(base, current, { result_type = "indices", algorithm = "histogram" })
		local signs = 0
		for _, hunk in ipairs(hunks) do
			signs = signs + math.max(1, hunk[4])
			if signs > 2000 then
				return {}
			end
		end
		-- A hunk gives counts, not which inserted lines replace removed lines.
		-- Keep mixed-hunk alignment bounded; this also stays off the UI thread.
		local function changed_lines(hunk, budget)
			local a, m, b, n = unpack(hunk)
			local changed = {}
			if m == 0 or n == 0 then
				return changed, budget
			end
			local simple = m == n or m * n > budget
			if not simple then
				for i = a, a + m - 1 do
					simple = simple or #old[i] > 256
				end
				for j = b, b + n - 1 do
					simple = simple or #new[j] > 256
				end
			end
			if simple then
				for j = 0, n - 1 do
					changed[j] = true
				end
				return changed, budget
			end
			local costs, steps = { [0] = {} }, {}
			for j = 0, n do
				costs[0][j] = j
			end
			for i = 1, m do
				costs[i], steps[i] = { [0] = i }, {}
				for j = 1, n do
					local left, right = old[a + i - 1], new[b + j - 1]
					local prefix, suffix, length = 0, 0, math.min(#left, #right)
					while prefix < length and left:byte(prefix + 1) == right:byte(prefix + 1) do
						prefix = prefix + 1
					end
					while suffix < length - prefix and left:byte(#left - suffix) == right:byte(#right - suffix) do
						suffix = suffix + 1
					end
					local similarity = (prefix + suffix) / math.max(1, #left, #right)
					local pair_cost = left == right and 0 or 1.8 - similarity
					if (left:match("^%s*$") ~= nil) ~= (right:match("^%s*$") ~= nil) then
						pair_cost = 1.95
					end
					local best, step = costs[i - 1][j - 1] + pair_cost, "pair"
					if costs[i][j - 1] + 1 < best then
						best, step = costs[i][j - 1] + 1, "add"
					end
					if costs[i - 1][j] + 1 < best then
						best, step = costs[i - 1][j] + 1, "delete"
					end
					costs[i][j], steps[i][j] = best, step
				end
			end
			local i, j = m, n
			while i > 0 and j > 0 do
				local step = steps[i][j]
				if step == "pair" then
					changed[j - 1] = true
					i, j = i - 1, j - 1
				elseif step == "add" then
					j = j - 1
				else
					i = i - 1
				end
			end
			return changed, budget - m * n
		end
		local marks, budget = {}, 4096
		for _, hunk in ipairs(hunks) do
			local removed, start, added = hunk[2], hunk[3], hunk[4]
			local changed
			changed, budget = changed_lines(hunk, budget)
			for offset = 0, math.max(1, added) - 1 do
				local text = added == 0 and "-" or (changed[offset] and "~" or "+")
				if added > 0 and removed > added and offset == added - 1 then
					text = "~-"
				end
				marks[#marks + 1] = {
					math.max(1, math.min(count, start + offset)) - 1,
					text,
					added == 0 and "DiffDelete" or (changed[offset] and "DiffChange" or "DiffAdd"),
				}
			end
		end
		return { marks = marks, hunks = hunks }
	end)
	return ok, ok and vim.mpack.encode(result) or tostring(result)
end

-- One worker plus one replaceable latest snapshot per buffer, never a FIFO of edits.
-- Retain the work object until its completion callback, including after BufUnload.
local function request_git_marks(buf, base, current, count, apply)
	local request = { base = base, current = current, count = count, apply = apply }
	local job = shared.git_diff_jobs[buf]
	if job then
		job.pending = request
		return
	end
	job = { request = request }
	shared.git_diff_jobs[buf] = job
	job.work = vim.uv.new_work(
		compute_git_marks,
		vim.schedule_wrap(function(ok, payload)
			if ok then
				local decoded, marks = pcall(vim.mpack.decode, payload)
				if decoded then
					local applied, err = pcall(job.request.apply, marks)
					if not applied then
						vim.notify("Git signs: " .. tostring(err), vim.log.levels.WARN)
					end
				end
			end
			local pending = job.pending
			job.pending = nil
			if pending then
				job.request = pending
				job.work:queue(pending.base, pending.current, pending.count)
			else
				shared.git_diff_jobs[buf] = nil
			end
		end)
	)
	job.work:queue(base, current, count)
end

local function queue_git_signs(buf)
	if not policy.allows(buf) then
		return
	end
	shared.git_sign_versions[buf] = {} -- unique token, also across unload/reload
	local version = shared.git_sign_versions[buf]
	local key = "git-signs:" .. buf
	shared.stop_git_sign_timer(buf)
	shared.cancel_command(key)
	if shared.git_diff_jobs[buf] then
		shared.git_diff_jobs[buf].pending = nil
	end
	local function clear_signs()
		if shared.git_sign_versions[buf] == version and vim.api.nvim_buf_is_loaded(buf) then
			vim.api.nvim_buf_clear_namespace(buf, shared.git_signs, 0, -1)
			actions.clear(buf)
		end
	end
	local timer
	timer = vim.defer_fn(function()
		if git_sign_timers[buf] ~= timer then
			return
		end
		git_sign_timers[buf] = nil
		if shared.git_sign_versions[buf] ~= version or not vim.api.nvim_buf_is_loaded(buf) then
			return
		end
		local file = vim.api.nvim_buf_get_name(buf)
		local limit = 256 * 1024
		if
			not policy.allows(buf)
			or file == ""
			or vim.fn.executable("git") == 0
			or vim.api.nvim_buf_line_count(buf) > 20000
			or vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) > limit
		then
			clear_signs()
			return
		end
		-- No temporary buffer/window switch and no BufEnter side effects.
		local root = shared.find_git_root(vim.fs.dirname(file))
		if not root then
			clear_signs()
			return
		end
		local tick = vim.api.nvim_buf_get_changedtick(buf)
		local stamp = git_index_stamp(root)
		local rendered = shared.git_sign_rendered[buf]
		if stamp and rendered and rendered.tick == tick and rendered.file == file and rendered.index == stamp then
			return
		end
		local current = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
		if vim.bo[buf].endofline then
			current = current .. "\n"
		end
		local function is_current()
			return shared.git_sign_versions[buf] == version
				and vim.api.nvim_buf_is_loaded(buf)
				and vim.api.nvim_buf_get_changedtick(buf) == tick
				and vim.api.nvim_buf_get_name(buf) == file
				and policy.allows(buf)
				and git_index_stamp(root) == stamp
		end
		local function apply_base(base)
			if not is_current() then
				return
			end
			if base:find("\0", 1, true) or current:find("\0", 1, true) then
				clear_signs()
				return
			end
			request_git_marks(buf, base, current, vim.api.nvim_buf_line_count(buf), function(result)
				if not is_current() then
					return
				end
				clear_signs()
				for _, mark in ipairs(result.marks or {}) do
					vim.api.nvim_buf_set_extmark(buf, shared.git_signs, mark[1], 0, {
						sign_text = mark[2],
						sign_hl_group = mark[3],
						priority = 5,
					})
				end
				shared.git_sign_rendered[buf] = { tick = tick, file = file, index = stamp }
				actions.render_deleted(buf, base, result.hunks or {})
			end)
		end
		local cached = git_base_cache[buf]
		if stamp and cached and cached.file == file and cached.root == root and cached.index == stamp then
			if cached.base then
				apply_base(cached.base)
			else
				clear_signs()
			end
			return
		end
		shared.run_command(key, { "git", "--no-pager", "show", ":./" .. file:sub(#root + 2) }, {
			cwd = root,
			max_bytes = limit,
			quiet = true,
			failed = function()
				if is_current() then
					git_base_cache[buf] = { file = file, root = root, base = false, index = stamp }
					clear_signs()
				end
			end,
		}, function(base)
			if is_current() then
				git_base_cache[buf] = { file = file, root = root, base = base, index = stamp }
				apply_base(base)
			end
		end)
	end, 200)
	git_sign_timers[buf] = timer
end
actions.setup(function(buf)
	git_status_cache = {}
	shared.git_sign_rendered[buf] = nil
	queue_git_signs(buf)
	refresh_git_status(buf, true)
	queue_netrw_git()
end)
vim.api.nvim_create_autocmd({
	"BufEnter",
	"BufWritePost",
	"TextChanged",
	"TextChangedI",
	"FocusGained",
	"ShellCmdPost",
	"TermLeave",
	"TermClose",
}, {
	group = vim.api.nvim_create_augroup("nopack-git-signs", { clear = true }),
	callback = function(args)
		if args.event == "TextChanged" or args.event == "TextChangedI" then
			local tick = vim.api.nvim_buf_get_changedtick(args.buf)
			if git_sign_changes[args.buf] == tick then
				return
			end
			git_sign_changes[args.buf] = tick
		end
		if
			args.event == "FocusGained"
			or args.event == "ShellCmdPost"
			or args.event == "TermLeave"
			or args.event == "TermClose"
		then
			local seen = {}
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				local buf = vim.api.nvim_win_get_buf(win)
				if not seen[buf] then
					seen[buf] = true
					queue_git_signs(buf)
				end
			end
		else
			queue_git_signs(args.buf)
		end
	end,
})
vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
	group = "nopack-git-signs",
	callback = function(args)
		git_sign_changes[args.buf] = nil
		shared.stop_git_sign_timer(args.buf)
		shared.git_sign_versions[args.buf], git_base_cache[args.buf], shared.git_sign_rendered[args.buf] = nil, nil, nil
		if shared.git_diff_jobs[args.buf] then
			shared.git_diff_jobs[args.buf].pending = nil
		end
		shared.cancel_command("git-signs:" .. args.buf)
	end,
})
vim.api.nvim_create_autocmd("User", {
	group = "nopack-git-signs",
	pattern = "NopackCancel",
	callback = function()
		vim.fn.timer_stop(netrw_git_timer)
		netrw_git_timer = -1
		stop_inline_blame()
		inline_blame.version = inline_blame.version + 1
		for buf in pairs(git_sign_timers) do
			shared.stop_git_sign_timer(buf)
		end
		shared.git_sign_versions = {}
		for _, job in pairs(shared.git_diff_jobs) do
			job.pending = nil
		end
	end,
})

vim.api.nvim_create_autocmd("User", {
	pattern = "NopackBufferRestricted",
	callback = function(args)
		local buf = args.data.buf
		shared.stop_git_sign_timer(buf)
		shared.git_sign_versions[buf], shared.git_sign_rendered[buf] = nil, nil
		if shared.git_diff_jobs[buf] then
			shared.git_diff_jobs[buf].pending = nil
		end
		shared.cancel_command("git-signs:" .. buf)
		if vim.api.nvim_buf_is_loaded(buf) then
			vim.api.nvim_buf_clear_namespace(buf, shared.git_signs, 0, -1)
		end
		if inline_blame.buf == buf then
			stop_inline_blame()
			inline_blame.version = inline_blame.version + 1
			clear_inline_blame(buf)
		end
	end,
})
