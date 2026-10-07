local policy = require("buffer_policy")
local shared = require("state")

-- =========================================
-- ======= PROJECT ROOT / CWD SYNC =======
-- =========================================
-- Search for Git within Python package or standard-library boundaries; prefer Git roots for ordinary files.
-- Tree, search and LSP share root rules; BufEnter aligns the editor window's lcd and tree.
-- Reuse roots until project/external changes; :NopackRefresh also forces discovery.
local markers = {
	"CMakeLists.txt",
	"compile_commands.json",
	"Makefile",
	"package.json",
	"pyproject.toml",
	"ty.toml",
	"pyrightconfig.json",
	"Cargo.toml",
	"WORKSPACE",
	"WORKSPACE.bazel",
	"MODULE.bazel",
	"buf.yaml",
	"verible.filelist",
}
local git_roots, project_roots = {}, {}
function shared.find_git_root(dir)
	local cached = git_roots[dir]
	if cached then
		return cached[1], cached[2]
	end
	local path = dir:gsub("/+$", "") .. "/"
	local packages, relative = path:match("^(.-/site%-packages/)(.*)$")
	if not packages then
		packages, relative = path:match("^(.-/dist%-packages/)(.*)$")
	end
	-- The first package directory is a browsing boundary, not evidence of Git ownership.
	-- A module directly in site-packages uses that directory as its boundary.
	local library_root = packages and (packages .. (relative:match("^[^/]+") or "")):gsub("/+$", "")
	local stop = library_root and vim.fs.dirname(library_root)
	local current = vim.fs.normalize(dir)
	local next_parent = vim.fs.parents(current)
	local git_root
	while current and current ~= stop do
		if vim.uv.fs_stat(current .. "/.git") then
			git_root = current
			break
		end
		-- Recognize the standard library by its contents, independent of Python version/layout.
		if
			not library_root
			and vim.fn.filereadable(current .. "/os.py") == 1
			and vim.fn.filereadable(current .. "/importlib/__init__.py") == 1
		then
			library_root = current
			break
		end
		current = next_parent(nil, current)
	end
	git_roots[dir] = { git_root, library_root }
	return git_root, library_root
end

function shared.find_project(dir)
	local cached = project_roots[dir]
	if cached then
		return unpack(cached)
	end
	local git_root, library_root = shared.find_git_root(dir)
	if git_root then
		cached = { git_root, true, true }
	elseif library_root then
		cached = { library_root, false, true }
	else
		local marker = vim.fs.find(markers, { path = dir, upward = true, type = "file", limit = 1 })[1]
		cached = { marker and vim.fs.dirname(marker) or dir, false, marker ~= nil }
	end
	project_roots[dir] = cached
	return unpack(cached)
end

-- Use the current file/tree's project or package, independent of the startup cwd.
shared.project_root = function()
	local dir = vim.bo.filetype == "flash-explorer" and require("explorer").root(vim.api.nvim_get_current_buf())
		or (policy.is_source(0) and vim.api.nvim_buf_get_name(0) ~= "" and vim.fn.expand("%:p:h"))
	if not dir then
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			local buf = vim.api.nvim_win_get_buf(win)
			local name = vim.api.nvim_buf_get_name(buf)
			if policy.is_editor(win) and name ~= "" then
				dir = vim.fn.fnamemodify(name, ":h")
				break
			end
		end
	end
	dir = dir or vim.fn.getcwd()
	return shared.find_project(dir)
end

-- The original config shares project cwd between file navigation, tree and searches.
local syncing_project = false
vim.api.nvim_create_autocmd("BufEnter", {
	group = vim.api.nvim_create_augroup("nopack-project-context", { clear = true }),
	callback = function()
		if syncing_project or not policy.is_editor(0) or vim.api.nvim_buf_get_name(0) == "" then
			return
		end
		local root, _, recognized = shared.project_root()
		if not recognized then
			return
		end
		local file = vim.api.nvim_buf_get_name(0)
		syncing_project = true
		if vim.fn.getcwd() ~= root then
			vim.cmd("lcd " .. vim.fn.fnameescape(root))
		end
		vim.api.nvim_exec_autocmds("User", {
			pattern = "NopackProjectContext",
			data = { root = root, file = file },
			modeline = false,
		})
		syncing_project = false
	end,
})
local function invalidate_project_roots()
	git_roots, project_roots = {}, {}
end
vim.api.nvim_create_autocmd({ "BufFilePost", "FocusGained", "ShellCmdPost", "TermLeave", "TermClose" }, {
	group = "nopack-project-context",
	callback = invalidate_project_roots,
})
vim.api.nvim_create_autocmd("BufWritePost", {
	group = "nopack-project-context",
	pattern = vim.list_extend(vim.deepcopy(markers), { ".git", "os.py", "__init__.py" }),
	callback = invalidate_project_roots,
})
vim.api.nvim_create_autocmd("User", {
	group = "nopack-project-context",
	pattern = { "NopackRefresh", "NopackExplorerChanged" },
	callback = invalidate_project_roots,
})
vim.api.nvim_create_user_command("NopackRefresh", function()
	vim.api.nvim_exec_autocmds("User", { pattern = "NopackRefresh", modeline = false })
	vim.api.nvim_exec_autocmds("BufEnter", { group = "nopack-project-context", buf = 0, modeline = false })
	vim.cmd("redrawstatus")
end, { desc = "Refresh project roots and formatter availability" })
